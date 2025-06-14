<#
This PowerShell script sets up SSH agent relaying for WSL (Windows Subsystem for Linux) using npiperelay.

Certain Linux applications don't like using the ssh.exe agent directly, so this script sets up a relay using npiperelay to forward the SSH agent socket from WSL to Windows.

Uses:
- Using 1Password SSH agent in WSL
- Using Ansible with Windows's OpenSSH agent
#>

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as an administrator."
    exit 1
}

$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -lt 7) {
    Write-Host "This script requires PowerShell version 7.0 or higher."
    exit 1
}

$wslInstalled = Get-Command wsl -ErrorAction SilentlyContinue
if (-not $wslInstalled) {
    Write-Host "WSL is not installed. Please install WSL first."
    exit 1
}

$npiperelayDownloadUrl = "https://github.com/jstarks/npiperelay/releases/latest/download/npiperelay_windows_amd64.zip"
$npiperelayZipPath = "$env:TEMP\npiperelay.zip"
$npiperelayExtractPath = "$env:TEMP\npiperelay"
$npiperelayExecutablePath = "$npiperelayExtractPath\npiperelay.exe"

Write-Host "Downloading npiperelay from $npiperelayDownloadUrl..."
Invoke-WebRequest -Uri $npiperelayDownloadUrl -OutFile $npiperelayZipPath

Write-Host "Extracting npiperelay to $npiperelayExtractPath..."
Expand-Archive -Path $npiperelayZipPath -DestinationPath $npiperelayExtractPath -Force

New-Item -Path 'C:\Program Files\npiperelay' -ItemType Directory -Force | Out-Null

Write-Host "Copying npiperelay executable to C:\Program Files\npiperelay..."
Copy-Item $npiperelayExecutablePath "C:\Program Files\npiperelay\npiperelay.exe" | Out-Null

if ($env:Path -notlike "*C:\Program Files\npiperelay*") {
    Write-Host "Adding npiperelay to system PATH..."
    $env:Path += ";C:\Program Files\npiperelay"
    [Environment]::SetEnvironmentVariable("Path", $env:Path, [System.EnvironmentVariableTarget]::Machine)
}
else {
    Write-Host "npiperelay is already in system PATH."
}

# output ssh script to file
$sshScript = @'
#!/bin/bash

echo "Running SSH Agent Relaying Setup..."

sudo apt -y update && sudo apt -y install socat

mkdir -p $HOME/.ssh

touch $HOME/.ssh/.agent-bridge.sh && chmod +x $HOME/.ssh/.agent-bridge.sh

echo "Creating SSH agent bridge script..."
cat << "EOF" > $HOME/.ssh/.agent-bridge.sh
# Credit to https://stuartleeks.com/posts/wsl-ssh-key-forward-to-windows/#final-solution
# Configure ssh forwarding
export SSH_AUTH_SOCK=$HOME/.ssh/agent.sock

# need `ps -ww` to get non-truncated command for matching
# use square brackets to generate a regex match for the process we want but that doesn't match the grep command running it!

ALREADY_RUNNING=$(ps -auxww | grep -q "[n]piperelay.exe -ei -s //./pipe/openssh-ssh-agent"; echo $?)
if [[ $ALREADY_RUNNING != "0" ]]; then
    if [[ -S $SSH_AUTH_SOCK ]]; then
        # not expecting the socket to exist as the forwarding command isn't running (http://www.tldp.org/LDP/abs/html/fto.html)
        echo "removing previous socket..."
        rm $SSH_AUTH_SOCK
    fi

    echo "Starting SSH-Agent relay..."
    # setsid to force new session to keep running
    # set socat to listen on $SSH_AUTH_SOCK and forward to npiperelay which then forwards to openssh-ssh-agent on windows
    (setsid socat UNIX-LISTEN:$SSH_AUTH_SOCK,fork EXEC:"npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork &) >/dev/null 2>&1
fi
EOF
chmod +x $HOME/.ssh/.agent-bridge.sh
echo "SSH agent bridge script created at $HOME/.ssh/.agent-bridge.sh"

echo "Adding SSH agent bridge script to .bashrc..."
LINE="source $HOME/.ssh/.agent-bridge.sh"
if ! grep -qxF "$LINE" "$HOME/.bashrc"; then
    echo "$LINE" >> $HOME/.bashrc
    echo "Added to .bashrc"
else
    echo "Already exists in .bashrc"
fi
'@

$normalisedScript = $sshScript -replace "`r`n", "`n" -replace "`r", "`n"
[System.IO.File]::WriteAllText("setup-ssh-agent-relaying.sh", $normalisedScript, [System.Text.UTF8Encoding]::new($false))

wsl bash setup-ssh-agent-relaying.sh

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to set up SSH agent relaying in WSL."
    exit $LASTEXITCODE
}
else {
    Write-Host "SSH agent relaying setup successfully in WSL."
    Write-Host "Cleaning up temporary files..."
    Remove-Item $npiperelayZipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $npiperelayExtractPath -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "setup-ssh-agent-relaying.sh" -Force -ErrorAction SilentlyContinue
    Write-Host "Temporary files cleaned up."
}

if ($Host.Name -eq 'ConsoleHost' -and !$psISE -and !$env:WT_SESSION) {
    Write-Host "`nPress any key to exit..."
    [void][System.Console]::ReadKey($true)
}
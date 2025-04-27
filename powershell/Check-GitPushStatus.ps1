<#
    .DESCRIPTION
        This script finds all Git repositories in a specified directory and checks their status.
        It checks if the remote repository is accessible, if the current branch has an upstream branch set,
        and if there are any commits to push or if the branch has diverged from the remote.

    .PARAMETER RootDirectory
        The root directory to search for Git repositories. Default is the current directory.

    .PARAMETER MaxDepth
        The maximum depth to search for Git repositories. Default is 2.
#>

param (
    [Parameter()]
    [string]$RootDirectory = (Get-Location).Path,

    [Parameter()]
    [int]$MaxDepth = 2
)

$ErrorActionPreference = "Stop"

Write-Host "Searching for Git repositories in $rootDirectory... (Max depth of $MaxDepth)" -ForegroundColor Cyan
$gitRepos = Get-ChildItem -Path $rootDirectory -Attributes Directory+Hidden -Recurse -Filter ".git" -Depth $MaxDepth | ForEach-Object { $_.Parent }
if ($gitRepos.Count -eq 0) {
    Write-Host "No Git repositories found $MaxDepth level deep in the specified directory." -ForegroundColor Red
    exit 0
}

Write-Host "Found $($gitRepos.Count) Git repositories." -ForegroundColor Green
Write-Host ""

foreach ($repo in $gitRepos) {
    Write-Host "Checking repository: $($repo.FullName)" -ForegroundColor Cyan

    Push-Location $repo.FullName

    try {
        # Check if remote exists
        $remote = git remote
        if (-not $remote) {
            Write-Host "⚠ No remote configured for this repository." -ForegroundColor Yellow
        }
        else {
            # Try fetching, catch fetch errors like "repository not found"
            $fetchOutput = git fetch 2>&1
            if ($fetchOutput -match "Repository not found" -or $fetchOutput -match "fatal") {
                Write-Host "❌ Remote repository not found or inaccessible!" -ForegroundColor Red
                Pop-Location
                Write-Host ""
                continue
            }

            # Get current branch
            $localBranch = git rev-parse --abbrev-ref HEAD

            # Check if branch has an upstream
            $upstreamCheck = git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
            if (-not $upstreamCheck) {
                Write-Host "⚠ No upstream branch set for '$localBranch'." -ForegroundColor Yellow
            }
            else {
                # Get status between local and remote
                $status = git status -uno

                if ($status -match "Your branch is up to date") {
                    Write-Host "✔ All changes pushed." -ForegroundColor Green
                }
                elseif ($status -match "Your branch is ahead of") {
                    Write-Host "⚠ You have commits to push!" -ForegroundColor Yellow
                }
                elseif ($status -match "have diverged") {
                    Write-Host "⚠ Branch has diverged from remote!" -ForegroundColor Red
                }
                elseif ($status -match "Your branch is behind") {
                    # Being behind is OK from a *push* point of view
                    Write-Host "✔ All changes pushed (but local is behind remote)." -ForegroundColor Green
                }
                else {
                    Write-Host "⚠ Unrecognized status. Full output:" -ForegroundColor Magenta
                    Write-Host $status -ForegroundColor DarkGray
                }
            }
        }
    }
    catch {
        Write-Host "Error checking repository $($repo.FullName): $_" -ForegroundColor Red
    }
    finally {
        Pop-Location
    }

    Write-Host ""
}

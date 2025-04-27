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
            Write-Host "⚠  No remote configured for this repository." -ForegroundColor Yellow
        }
        else {
            # Try fetching, catch fetch errors like "repository not found"
            $fetchOutput = git fetch --all --prune 2>&1
            if ($fetchOutput -match "Repository not found" -or $fetchOutput -match "fatal") {
                Write-Host "❌  Remote repository not found or inaccessible!" -ForegroundColor Red
                Pop-Location
                Write-Host ""
                continue
            }

            $branches = git for-each-ref --format="%(refname:short) %(upstream:short)" refs/heads/ | ForEach-Object {
                $parts = $_ -split " "
                [PSCustomObject]@{
                    Branch   = $parts[0]
                    Upstream = if ($parts.Count -gt 1) { $parts[1] } else { $null }
                }
            }

            $notSet = ($branches | Where-Object { $_.Upstream -eq $null }).Count
            if ($notSet -gt 0) {
                Write-Host "$notSet branches have no upstream set" -ForegroundColor DarkGray
            }

            foreach ($branch in $branches) {
                if ($branch.Upstream) {
                    git show-ref --verify --quiet "refs/remotes/$($branch.Upstream)"

                    if ($LASTEXITCODE -ne 0) {
                        Write-Host "⚠  Upstream branch '$($branch.Upstream)' does not exist for branch '$($branch.Branch)'." -ForegroundColor Yellow
                        continue
                    }

                    $counts = git rev-list --left-right --count "$($branch.Branch)...$($branch.Upstream)"
                    $split = $counts -split "\s+"
                    $behind = $split[0]
                    $ahead = $split[1]

                    if ($behind -gt 0 -and $ahead -gt 0) {
                        Write-Host "🚩  Branch '$($branch.Branch)' has diverged from its upstream '$($branch.Upstream)' (behind by $behind commits, ahead by $ahead commits)." -ForegroundColor Red
                    }
                    elseif ($behind -gt 0) {
                        Write-Host "✔  Branch '$($branch.Branch)' is up to date with '$($branch.Upstream)' (but is behind by $behind commits)" -ForegroundColor Green
                    }
                    elseif ($ahead -gt 0) {
                        Write-Host "🚩  Branch '$($branch.Branch)' is ahead of its upstream '$($branch.Upstream)' by $ahead commits." -ForegroundColor Red
                    }
                    else {
                        Write-Host "✔  Branch '$($branch.Branch)' is up to date with '$($branch.Upstream)'." -ForegroundColor Green
                    }
                }
            }

            Write-Host ""

            # Get current branch
            $localBranch = git rev-parse --abbrev-ref HEAD

            if (-not (git status -s)) {
                Write-Host "✔  No uncommitted changes on current branch $localBranch" -ForegroundColor Green
            }
            else {
                Write-Host "🚩  Uncommitted changes detected on current branch $localBranch!" -ForegroundColor Red
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

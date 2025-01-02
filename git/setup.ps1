param(
    [bool]$RunFunctions = $False
)

function Test-Git {

    if ( $localDebug ) { Write-Host "Checking if Git is installed..." }

    $commandCheck = $(Get-Command -Name git -ErrorAction SilentlyContinue)

    if ( $commandCheck ) {

        if ( $localDebug ) { Write-Host "Git is installed (" (Get-Git) ")." }

        return $True

    } else {

        if ( $localDebug ) { Write-Host "Git was not found." }

        return $False

    }

}


function Get-Git {

    $rawVersion = $(git --version)

    if ( ( $rawVersion[1] -match 'version (\d+\.\d+\.\d+)' ) ) {

        return $matches[1]

    } else {

        Write-Warning "Could not extract a valid version number (${rawVersion})."

        return $null

    }

}


function Install-Git {

    if ( $localDebug ) { Write-Host "Installing Git..." }

    try {

        # Install using winget
        winget install -e --id Git.Git --accept-package-agreements --accept-source-agreements --silent

        # Refresh the PATH variable in the current session (in order for the 'git' command to work)
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")

        if (Test-Git) {

            if ( $localDebug ) { Write-Host "Git installed successfully." }

            return $True

        } else {

            throw "Git installation failed."

        }
    }
    catch {

        Write-Host "Error: $_"

        return $False

    }

}


function UpdateAvailable {

    Write-Host "Checking if update available..."

    return $(winget upgrade | Select-String -Pattern "Git.Git")

}



function Get-GitAvailable {

    try {

        $result = $(winget upgrade | Select-String -Pattern "Git.Git")

        if ( $result ) {

            return $result

        }

    }
    catch {

        return ""

    }

}


function Update-Git {

    if ( $localDebug ) { Write-Host "Updating Git..." }

    winget upgrade -n Git.Git

}


function Invoke-GitFunctions {

    Get-GitAvailable

    if ( -not ( Get-Git ) ) {

        Install-Git

    } else  {

        Update-Git

    }

    Get-Git

}


$localDebug = $global:debug


if ($ExecuteGitFunctions) {

    if ($localDebug) { Write-Host "Executing Invoke-GitFunctions..." }

    Invoke-GitFunctions

}
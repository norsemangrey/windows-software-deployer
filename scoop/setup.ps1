function Test-Scoop {

    if ( $localDebug ) { Write-Host "Checking if Scoop is installed..." }

    $pathCheck = $(Test-Path $env:USERPROFILE\scoop)

    $commandCheck = $(Get-Command -Name scoop -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Path -ErrorAction SilentlyContinue)

    if ( $pathCheck -and $commandCheck ) {

        if ( $localDebug ) { Write-Host "Scoop is installed (" (Get-Scoop) ")." }

        return $True

    } else {

        if ( $localDebug ) { Write-Host "Scoop was not found." }

        return $False

    }

}


function Install-Scoop {

    if ( $localDebug ) { Write-Host "Installing Scoop..." }

    try {

        Invoke-Expression "& {$(Invoke-RestMethod get.scoop.sh)} -RunAsAdmin" | Out-Null

        if (Test-Scoop) {

            if ( $localDebug ) { Write-Host "Scoop installed successfully." }

            Complete-Scoop

            return $True

        } else {

            throw "Scoop installation failed."

        }
    }
    catch {

        Write-Host "Error: $_"

        return $False

    }

}


function Complete-Scoop {

    if ( $localDebug ) { Write-Host "Adding additional buckets to Scoop..." }

    $wantedBuckets = @(
        "main",
        "extras",
        "nerd-fonts"
    )

    $installedBuckets = $(scoop bucket list).Name

    $bucketsToAdd = $wantedBuckets | Where-Object { $_ -notin $installedBuckets }

    $bucketsToAdd | ForEach-Object {

        try {

            $err = & scoop bucket add $_ 6>&1

            if ($LASTEXITCODE -eq 0 -or ( $( $err | Out-String).Contains("bucket already exists"))) {

                Write-Host "Scoop buckets added successfully. ($_)"

                git config --global --add safe.directory "$Env:USERPROFILE/scoop/apps/scoop/${_}"

            } else {

                throw "Adding scoop buckets failed. ($_)"

            }

        }
        catch {

            Write-Host "Error: $_"

        }

    }

    Update-Scoop

}


function Update-Scoop {

    if ( $localDebug ) { Write-Host "Updating Scoop..." }

    scoop update

}


function Get-Scoop {

    $rawVersion = $(scoop --version 6>&1)

    if ( ( $rawVersion[1] -match 'version (\d+\.\d+\.\d+)' ) ) {

        return $matches[1]

    } else {

        Write-Warning "Could not extract a valid version number (${rawVersion})."

        return $null

    }

}


function Get-ScoopAvailable {

    try {

        $apiUrl = "https://api.github.com/repos/ScoopInstaller/Scoop/releases/latest"

        $response = Invoke-RestMethod -Uri $apiUrl

        if ( $response ) {

            foreach ($release in $response) {

                if (-not $release.prerelease) {

                    $latestVersion = $release.tag_name
                    break

                }
            }

            return $latestVersion

        }

    }
    catch {

        return ""

    }

}


function Invoke-ScoopFunctions {

    Get-ScoopAvailable

    if ( -not ( Test-Scoop ) ) {

        Install-Scoop

    } else  {

        Update-Scoop

    }

    Get-Scoop

}


$localDebug = $global:debug
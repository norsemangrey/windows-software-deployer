function Test-Wsl {

    # Test that the WSL directory exists
    $pathCheck = $(Test-Path "C:\Windows\System32\wsl.exe")

    if (-not $pathCheck) {

        Write-Host "WSL is not installed."

    }

    # Check that WSL Windows features are installed
    $featuresCheck = Test-WslFeatures

    # Test that the WSL command is available
    $commandCheck = Test-WslCommand

    # Test if there are any distributions installed
    $distributionsCheck = Test-WslDistribution

    # Return results
    if ( $pathCheck -and $commandCheck -and $featuresCheck -and $distributionsCheck) { return $True } else { return $False }

}


function Test-WslCommand {

    try {

        $output = $(& wsl --version)

        $output[0].Replace("`0",'') -match '\d+(\.\d+)+' | Out-Null

        if ($matches[0]) {

            return $True

        } else {

            return $False

        }

    } catch {

        return $False

    }

}


function Test-WslDistribution {

    try {

        $distributions = wsl --list --quiet 2>$null

        if ($distributions) {

            return $True

        } else {

            return $False

        }

    } catch {

        return $False

    }

}


function Test-WslFeatures {

    $wsl = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux).State
    $vmp = (Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform).State

    if ($wsl -eq "Enabled" -and $vmp -eq "Enabled") {

        return $True

    } elseif ($wsl.Installed) {

        return $False

    } else {

        return $False

    }

}


function Install-Wsl {

    try {

		# Enable WSL feature
		$wsl = Enable-WindowsFeature -featureName "Microsoft-Windows-Subsystem-Linux"

		# Enable VMP feature
		$vmp = Enable-WindowsFeature -featureName "VirtualMachinePlatform"

        # Check results from enabling Windows features
        if ( ( $wsl -eq 1 ) -or  ( $vmp -eq 1 ) ) {

            $rebootRequired = $True

        } elseif ( ( $wsl -eq -1 ) -or  ( $vmp -eq -1 ) ) {

            throw "Failed to enable required Windows feature."

            exit 1

        } elseif ( ( $wsl -eq 0 ) -and ( $vmp -eq 0 ) ) {

            # Enable WSL version 2
            & wsl --set-default-version 2

            # Upgrade WLS from the MS Store
            if ( -not $( Test-WslCommand ) ) {

                Update-Wsl

            }

            # Install a Distribution if non present
            if ( -not $( Test-WslDistribution ) ) {

                Complete-Wsl

            }

        }

        if ( $rebootRequired ) {

            Write-Host "WSL install requires reboot to continue."

            return "Reboot"

        }

        if (Test-Wsl) {

            if ( $localDebug ) { Write-Host "WSL installed successfully." }

            return $True

        } else {

            throw "WSL installation failed."

        }
    }
    catch {

        Write-Warning "Enabling WSL failed (${_})"

        return $False

    }

}


function Complete-Wsl {

    if ( $localDebug ) { Write-Host "Removing default distribution supplied with Windows..." }

    $defaultDistributionName = "Ubuntu on Windows"

    $defaultDistribution = winget list --name $defaultDistributionName | Select-String -Pattern $defaultDistributionName

    # Check if $app contains any output (indicating the app is installed)
    if ($defaultDistribution) {

        # Parse the output to get the App ID (assuming it's the first column in the output)
        $defaultDistributionId = ($defaultDistribution -replace $defaultDistributionName).Trim().Split(" ")[0]

        if ( $localDebug ) { Write-Output "Default distribution '$defaultDistributionName' is present. Uninstalling..." }

        # Uninstall the application using the ID
        winget uninstall --id $defaultDistributionId

    } else {

        if ( $localDebug ) { Write-Output "Default distribution '$defaultDistributionName' is not installed." }

    }

    if ( $localDebug ) { Write-Host "Installing Linux distribution..." }

    wsl --install --distribution "Ubuntu" --no-launch

    if ( $localDebug ) { Write-Host "Completing Ubuntu setup..." }

    ubuntu.exe install --root

}


function Update-Wsl {

    if ( $localDebug ) { Write-Host "Updating WSL..." }

    wsl --update

}


function Get-Wsl {

    $output = $(& wsl --version)

    $output[0].Replace("`0",'') -match '\d+(\.\d+)+' | Out-Null

    return $matches[0]

}


function Get-WslAvailable {

    try {

        $apiUrl = "https://api.github.com/repos/microsoft/wsl/releases"

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


function Enable-WindowsFeature {
    param (
        [string]$featureName
    )

    # Check if the feature is enabled
    $featureStatus = Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -eq $featureName }

    # Check the feature status
    if ($featureStatus -and $featureStatus.State -eq "Enabled") {

        if ( $localDebug ) { Write-Host "Windows feature $featureName is already enabled." }

        return 0

    } else {

        if ( $localDebug ) { Write-Host "Enabling Windows feature $featureName..." }

        # Enable feature without immediate restart
        Enable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart -All

        # Get feature status after attempting to enable
        $featureStatusAfterEnable = Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -eq $featureName }

        # Check if the feature is now enabled
        if ($featureStatusAfterEnable -and $featureStatusAfterEnable.State -eq "Enabled") {

            if ( $localDebug ) { Write-Host "Windows feature $featureName has been successfully enabled." }

            return 1

        } else {

            Write-Host "Failed to enable $featureName."

            return -1

        }

    }

}

function Invoke-WslFunctions {

    Get-WslAvailable

    if ( -not ( Test-Wsl ) ) {

        Install-Wsl

    } else  {

        Update-Wsl

    }

    Get-Wsl

}


$localDebug = $global:debug

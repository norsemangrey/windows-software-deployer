function Test-WinGetAll {

    return (Test-WinGetCli) -and (Test-WinGetClient)

}


function Test-WinGet {

    if ( $localDebug ) { Write-Host "Checking if WinGet Cli is installed..." }

    $commandCheck = $(Get-Command -Name winget -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Path -ErrorAction SilentlyContinue)

    if ( $commandCheck ) {

        if ( $localDebug ) { Write-Host "WinGet package manager is installed (" (Get-WinGet) ")." }

        return $True

    } else {

        if ( $localDebug ) { Write-Host "WinGet package manager was not found." }

        return $False

    }

}


function Test-WinGetClient {

    if ( $localDebug ) { Write-Host "Checking if WinGet Client (PowerShell module) is installed..." }

    $isInstalled = Get-InstalledPSResource -Name Microsoft.WinGet.Client -ErrorAction SilentlyContinue

    if ( $isInstalled ) {

        if ( $localDebug ) { Write-Host "WinGet Client module for PowerShell is installed (" (Get-WinGet) ")." }

        return $True

    } else {

        if ( $localDebug ) { Write-Host "WinGet Client module for PowerShell was not found." }

        return $False

    }

}


function Install-WinGet {

    $result = Install-WinGetCli

    if ( ($result) ) {

        return Install-WinGetClient

    } else {

        return $False

    }

}


function Install-WinGet {

    # Build command string -> source scrip and install
    $command = ". \`"$PSCommandPath\`" ; Install-WinGetAndDependencies"

    # Run the WinGet install in new shell as administrator.
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -NoExit -ExecutionPolicy Bypass -Command `"$command`"" -Wait

    # Do final test to verify install
    if ( -not( Test-Path $env:USERPROFILE\AppData\Local\Microsoft\WindowsApps\winget.exe ) ) {

        Write-Error "Failed to install Microsoft Desktop App (WinGet) package manager."

        return $False

    } else {

        Complete-WinGet

        return $True

    }

}


function Install-WinGetAndDependencies {

    #TODO: This might not work yet, but winget should be installed default on Windows 11

    function IsAppxPackageInstalled($packageName, $requiredVersion) {

        $installedPackage = Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue

        return ( $null -ne $installedPackage ) -and ( $installedPackage.Version -ge $requiredVersion )

    }

    Write-Host "Checking WinGet dependencies..."

    # Install NuGet package provider for PowerShell package management if not already installed
    if ( $null -eq $(Get-PackageProvider -Name NuGet -Force -ErrorAction SilentlyContinue) ) {

        Write-Host "Installing NuGet package provider..."

        try {

            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop

        } catch {

            Write-Error "Error: Failed to install NuGet package provider: $_"
            return $False

        }

    } else {

        Write-Host "NuGet package provider is already installed"

    }

    # Install PowerShellGet module for managing PowerShell modules if not already installed
    if ( $null -eq $(Get-Package -Name PowerShellGet -ErrorAction SilentlyContinue) ) {

        Write-Host "Installing PowerShellGet module..."

        try {

            Install-Module PowerShellGet -Force -AllowClobber -ErrorAction Stop

        } catch {

            Write-Error "Error: Failed to install PowerShellGet module: $_"
            return $False

        }

    } else {

        Write-Host "PowerShellGet package manager is already installed"

    }


    $VCLibsPackageName = 'Microsoft.VCLibs.140.00.UWPDesktop'
    $VCLibsDownloadUrl = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"

    # Install Microsoft Visual C++ Libraries package if not already installed
    if (-not (IsAppxPackageInstalled $VCLibsPackageName)) {

        Write-Host "Installing Microsoft Visual C++ Libraries package..."

        try {

            Invoke-WebRequest -Uri $VCLibsDownloadUrl -OutFile ".\$VCLibsPackageName.appx" -ErrorAction Stop

        } catch {

            Write-Error "Error: Failed to download Microsoft Visual C++ Libraries package: $_"
            return $False

        }

        try {

            Add-AppxPackage -Path ".\$VCLibsPackageName.appx" -ErrorAction Stop

        } catch {

            Write-Error "Error: Failed to install Microsoft Visual C++ Libraries package: $_"
            return $False

        }

    } else {

        Write-Host "Microsoft Visual C++ Libraries package is already installed"

    }

    $UIXamlPackageName = 'Microsoft.UI.Xaml.2.7'
    $UIXamlDownloadUrl = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.7.3/Microsoft.UI.Xaml.2.7.x64.appx"

    # Install Microsoft UI XAML package if not already installed
    if (-not (IsAppxPackageInstalled $UIXamlPackageName)) {

        Write-Host "Installing Microsoft UI XAML package..."

        try {

            Invoke-WebRequest -Uri $UIXamlDownloadUrl -OutFile ".\$UIXamlPackageName.appx" -ErrorAction Stop

        } catch {

            Write-Error "Error: Failed to download Microsoft UI XAML package: $_"
            return $False

        }

        try {

            Add-AppxPackage -Path ".\$UIXamlPackageName.appx" -ErrorAction Stop

        } catch {

            Write-Error "Error: Failed to install Microsoft UI XAML package: $_"
            return $False

        }

    } else {

        Write-Host "Microsoft UI XAML package is already installed"

    }


    Write-Host "Installing Microsoft Desktop App (WinGet) package manager..."

    # Download Microsoft Desktop App Installer package
    $DesktopInstallerDownloadUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"

    # TODO: Change back to original output file when finished testing
    $DesktopInstallerOutputFile = ".\MicrosoftDesktopAppInstaller.msixbundle"
    #$DesktopInstallerOutputFile = Join-Path $PSScriptRoot MicrosoftDesktopAppInstaller.msixbundle

    try {

        # TODO: Add this back once finished testing
        #Invoke-WebRequest -Uri $DesktopInstallerDownloadUrl -OutFile $DesktopInstallerOutputFile -ErrorAction Stop

    } catch {

        Write-Error "Error: Failed to download Microsoft Desktop App (WinGet) package manager package: $_"
        return $False

    }

    # Download license file for Microsoft Desktop App Installer
    $LicenseFileDownloadUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/24146eb205d040e69ef2d92d7034d97f_License1.xml"
    $LicenseFileOutputPath = ".\License1.xml"

    try {

        #Invoke-WebRequest -Uri $LicenseFileDownloadUrl -OutFile $LicenseFileOutputPath -ErrorAction Stop

    } catch {

        Write-Error "Error: Failed to download license file for Microsoft Desktop App (WinGet) package manager: $_"
        return $False

    }

    # Add provisioned package for Microsoft Desktop App Installer with its license
    try {

        Add-AppxProvisionedPackage -Online -PackagePath $DesktopInstallerOutputFile -LicensePath $LicenseFileOutputPath -Verbose | Out-Null

        #Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -NoExit -ExecutionPolicy Bypass -Command $command" -Wait

    } catch {

        Write-Error "Error: Failed to provision Microsoft Desktop App (WinGet) package manager package: $_"
        return $False

    }

    # Allow a little time before check
    Start-Sleep -Milliseconds 10000

}


function Install-WinGetClient {

    if ( $localDebug ) { Write-Host "Installing WinGet Client module for PowerShell..." }

    try {

        $errorMessage = $( Install-PSResource -Name Microsoft.WinGet.Client -AcceptLicense 2>&1 )

        if ( -not $errorMessage ) {

            if ( Test-WinGetClient ) {

                if ( $localDebug ) { Write-Host "WinGet Client module for PowerShell successfully installed." }

                return $True

            } else {

                Write-Warning "Potential package install issue (could not find installed version)."

            }

        } else {

            throw $errorMessage

        }

    }
    catch {

        Write-Warning "Could not install package -> $($_.Exception.Message)"

        return $False

    }

}


function Complete-WinGet {

    # Set the PowerShell Gallery as a trusted repository for PowerShell modules
    try {

        Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop

    } catch {

        Write-Error "Error: Failed to set PowerShell Gallery as a trusted repository: $_"

    }

}


function Update-WinGet {

    try {

        winget upgrade winget

        return $True

    }
    catch {

        Write-Host "Error: $_"

        return $False

    }

}


function Get-WinGet {

    $rawVersion = $(winget --version 6>&1)

    if ( ( $rawVersion -match '\d+(\.\d+){0,2}' ) ) {

        return $matches[0]

    } else {

        Write-Warning "Could not extract a valid version number (${rawVersion})."

        return $null

    }

}


function Get-WinGetAvailable {

    try {

        $apiUrl = "https://api.github.com/repos/microsoft/winget-cli/releases"

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
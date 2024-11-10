function Test-PSGet {

    if ( $localDebug ) { Write-Host "Checking if modern PowerShellGet is installed..." }

    $commandCheck = $(Get-InstalledModule PowerShellGet -ErrorAction SilentlyContinue).Version

    if ( $commandCheck ) {

        if ( $localDebug ) { Write-Host "Modern PowerShellGet is installed (" $commandCheck ")." }

         return $True

    } else {

        if ( $localDebug ) { Write-Host "Modern PowerShellGet was not found." }

        return $False

    }

}


function Install-PSGet {

    if ( $localDebug ) { Write-Host "Installing modern PowerShellGet..." }

    try {

        Install-Module -Name 'PowerShellGet' -AllowClobber -Force -Scope 'CurrentUser' -Repository 'PSGallery'

        if (Test-PSGet) {

            if ( $localDebug ) {  Write-Host "Modern PowerShellGet installed successfully." }

            Complete-PSGet

            return $True

        } else {

            throw "Modern PowerShellGet installation failed."

        }

    }
    catch {

        Write-Host "Error: $_"

        return $False

    }


}


function Complete-PSGet {

    if ( $localDebug ) { Write-Host "Removing old PowerShell version if present..." }

    Remove-Item -Recurse -Force "C:\Program Files\WindowsPowerShell\Modules\PowerShellGet\1.0.0.1" -ErrorAction SilentlyContinue

    if ( $localDebug ) { Write-Host "Reloading PowerShellGet module..." }

    Remove-Module PowerShellGet
    Import-Module PowerShellGet

    if ( $localDebug ) { Write-Host "Adding PSGallery to trusted sources..." }

    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted

}


function Get-PSGet {

    $version = $(Get-InstalledModule PowerShellGet -ErrorAction SilentlyContinue).Version

    if ( $version ) {

        return $version

    } else {

        return $null

    }

}


function Update-PSGet {

    if ( $localDebug ) { Write-Host "Updating PowerShellGet..." }

    try {

        Update-Module -Name 'PowerShellGet' -Force -Scope 'CurrentUser'

        return $True

    }
    catch {

        Write-Host "Error: $_"

        return $False

    }

}


function Get-PSGetAvailable {

    $packageAvailable = $(Find-Module "PowerShellGet").Version

    if ( $packageAvailable ) {

        return $packageAvailable

    } else {

        return $null

    }

}


function Invoke-PSGetFunctions {

    Get-PSGetAvailable

    if ( -not ( Test-PSGet ) ) {

        Install-PSGet

    } else  {

        Update-PSGet

    }

    Get-PSGet

}


$localDebug = $global:debug
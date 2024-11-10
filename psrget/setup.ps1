function Test-PSResourceGet {

    if ( $localDebug ) { Write-Host "Checking if PSResourceGet is installed..." }

    $versionCheck = $(Get-InstalledModule 'Microsoft.PowerShell.PSResourceGet' -ErrorAction SilentlyContinue).Version

    if ( $versionCheck ) {

        if ( $localDebug ) { Write-Host "PSResourceGet is installed (" $versionCheck ")." }

         return $True

    } else {

        if ( $localDebug ) { Write-Host "PSResourceGet was not found." }

        return $False

    }

}


function Install-PSResourceGet {

    if ( $localDebug ) { Write-Host 'Installing PSResourceGet...' }

    try {

        Install-Module -Name 'Microsoft.PowerShell.PSResourceGet' -AllowClobber -Force -Scope 'CurrentUser' -Repository 'PSGallery'

    }
    catch {

        Write-Host "Error: $_"

        return $False

    }

    Complete-PSResourceGet

    if (Test-PSResourceGet) {

        if ( $localDebug ) { Write-Host "PSResourceGet installed successfully." }

        return $True

    } else {

        throw "PSResourceGet installation failed."

        return $False

    }

}


function Complete-PSResourceGet {

    if ( $localDebug ) { Write-Host "Importing PSResourceGet and setting trusted repository..." }

    Import-Module 'Microsoft.PowerShell.PSResourceGet'

    Set-PSResourceRepository -Name 'PSGallery' -Trusted

}


function Get-PSResourceGet {

    $version = $(Get-InstalledModule 'Microsoft.PowerShell.PSResourceGet' -ErrorAction SilentlyContinue).Version

    if ( $version ) {

        return $version

    } else {

        return $null

    }

}


function Update-PSResourceGet {

    if ( $localDebug ) { Write-Host "Updating PSResourceGet..." }

    try {

        Update-PSResource -Name 'Microsoft.PowerShell.PSResourceGet' -Force -Scope 'CurrentUser'

        return $True

    }
    catch {

        Write-Host "Error: $_"

        return $False

    }

}


function Get-PSResourceGetAvailable {

    $packageAvailable = $(Find-Module 'Microsoft.PowerShell.PSResourceGet').Version

    if ( $packageAvailable ) {

        return $packageAvailable

    } else {

        return $null

    }

}


function Invoke-PSResourceGetFunctions {

    Get-PSResourceGetAvailable

    if ( -not ( Test-PSResourceGet ) ) {

        Install-PSResourceGet

    } else  {

        Update-PSResourceGet

    }

    Get-PSResourceGet

}


$localDebug = $global:debug
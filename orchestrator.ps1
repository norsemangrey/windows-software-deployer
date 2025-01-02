Set-ExecutionPolicy RemoteSigned -Scope CurrentUser


# Import script for Topological Sort
. (Join-Path $PSScriptRoot sort.ps1)


#region: Classes & Variables

class Managers {

    [bool] $psrget = $False
    [bool] $winget = $False
    [bool] $scoop  = $False

}

class Package {
    [string]$Manager=""
    [string]$Id=""
    [string]$Source=""
}

class Software {
    [string]$Name=""
    [string]$Alias=""
    [Package[]]$Package=@([Package]::new())
    [int]$Selected=0
    [string]$Version=""
    [string]$Available=""
    [string[]]$Dependencies=@()
    [string[]]$Urls
    [bool]$Prerequisite=$false
    [int]$Sort=0
    [action]$Action=[action]::None
    [bool]$Installed=$false
    [bool]$InManifest=$false
}

#TODO: Future use?
class Collection {

    [Software[]]$Software=@()

    # Method to print the Packages array as a table
    [void]PrintCollection() {

        if ($this.Software.Count -eq 0) {

            Write-Host "No software available."
            return

        }

        Write-Host($this.Software | Format-Table -AutoSize | Out-String)

    }

}

#TODO: Future use?
class Install : Software {
    [Package]$Package
}


enum action
{
    None = 0
    Install = 1
    Update = 2
    Remove = 3
}


# Global variables
$managerAvailable = [Managers]::new()
$managers = @("psrget", "winget", "scoop")
$inventory = @()
$manifest =  @()
$debug = $True

#endregion


#region: Helper Functions

# Helper function to log/write messages
function Write-Message {
    param (
        [string]$Message,
        [string]$Type = 'INFO'
    )

    # Initialize values
    $timestamp = $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    $label = $Type.ToUpper()

    # Calculate padding based on the longest label
    $maxLabelLength = 7
    $paddingLength  = $maxLabelLength - $label.Length

    if ( $paddingLength -lt 0 ) { $padding = '' } else { $padding = (' ' * $paddingLength) }

    # Construct the formatted message with padding after the label
    $formattedMessage = "[$timestamp] [$label] $padding $Message"

    # Set color based on the type and output message
    switch ($label) {

        'INFO' {
            Write-Host $formattedMessage -ForegroundColor Green
        }
        'ERROR' {
            Write-Host $formattedMessage -ForegroundColor Red
        }
        'WARNING' {
            Write-Host $formattedMessage -ForegroundColor Yellow
        }
        'DEBUG' {
            if ( $debug ) { Write-Host $formattedMessage -ForegroundColor Cyan }
        }
        default {
            Write-Host $formattedMessage -ForegroundColor White
        }

    }

    # Path to the log file
    $logFilePath = (Join-Path $PSScriptRoot "log.txt")

    # Append the formatted message to the log file
    $formattedMessage | Out-File -FilePath $logFilePath -Append

}

# Helper function to print collection as table
function Show-Collection {
    param (
        [Software[]] $collection,
        [string[]] $Exclude = @()
    )

    # Get all property names of the Software class and exclude specified properties
    $visibleProperties = [Software]::new().PSObject.Properties.Name | Where-Object { $_ -notin $Exclude }

    # Display the collection as a table with specified properties, outputting only to the console
    $collection | Select-Object -Property $visibleProperties | Format-Table -AutoSize | Out-Host

}

#endregion


#region Main Function

function Start-PackageOrchestrator {

    Write-Message "Starting package orchestrator..." "INFO"

    # PREPARATIONS

    # Check if NuGet is installed
    $nugetProvider = Get-PackageProvider -Name NuGet -Force -ErrorAction SilentlyContinue

    # Install NuGet if it is not already installed
    if (-not $nugetProvider) {

        Write-Message "NuGet provider not found. Installing..." "DEBUG"

        [void](Install-PackageProvider -Name NuGet -Force -ForceBootstrap -Scope CurrentUser)

    } else {

        Write-Message "NuGet provider is already installed." "DEBUG"

    }

    # IMPORT MANIFEST

    Write-Message "Importing user manifest from file..." "INFO"

    # Get manifest from file
    Import-FromJsonFile "manifest" | ForEach-Object {

        # Convert JSON object from manifest file to Software a instance
        $manifestSoftware = ConvertTo-Class -SourceObject $_ -TargetType ([Software])

        # Set the manifest property to True as it is coming from the manifest
        $manifestSoftware.InManifest = $true

        # Append the modified instance directly to the SoftwareList array
        $global:manifest += @($manifestSoftware)

    }

    # Print imported manifest
    Show-Collection $global:manifest -Exclude @("Sort", "InManifest", "Selected", "Version", "Available", "Action", "Installed")


    # INSTALL & CHECK PACKAGE MANAGERS

    Write-Message "Checking available package managers and installing if required..." "INFO"

    # Get data and build a package list from the manifest
    $global:manifest| Where-Object { $_.prerequisite } | ForEach-Object {

        # Get package details for "prerequisite" software
        Get-Package $_

        # Check if there is an action on the package
        if ( $_.Action -ne [action]::None ) {

            # Build action method name from package data and execute
            & "$([action].GetEnumName($_.Action))-Package" $_ | Out-Null

        }

    }

    # Set managers available based on inventory status
    $managers | ForEach-Object {

        # Check if manager software is in inventory
        if ( -not (Test-Dependency @($_ ) ) ) {

            # Set manager as available
            $global:managerAvailable.$($_) = $true

        } else {

            Write-Message "Could not confirm manager available ($($_)). Package handling for this manager will be ignored." "WARNING"

        }

    }

    # BUILD INVENTORY

    Write-Message "Checking system for installed software..." "INFO"

    # Get installed applications for all package managers
    $managers | ForEach-Object {

        # Find installed software foe manager if available
        if ( $global:managerAvailable.$($_) ) { Find-Packages $_ }

    }

    # TODO: Need to include package manager as a dependency on each object when not custom?


    # CHECK MANIFEST PACKAGES

    Write-Message "Checking software from manifest, updating details and action..." "INFO"

    # Check packages in manifest and update details and inventory
    $global:manifest | ForEach-Object { Get-Package $_ }

    # Print updated manifest
    Show-Collection $global:manifest -Exclude @("InManifest", "Sort")

    #TODO: Cross-reference with inventory to confirm manager/id??

    ## CREATE PLAN

    Write-Message "Creating plan for manifest software with sorted, actioned items..." "INFO"

    # Filter out packages from manifest with an action
    $actionedPackages = $global:manifest | Where-Object { $_.Action -ne [action]::None }

    # Add sort number to packages based on dependencies and sort them
    $plan = Get-TopologicalSort $actionedPackages "Alias" "Dependencies" | Sort-Object -Property Sort

    # Print updated manifest
    Show-Collection $plan -Exclude @("InManifest", "Urls", "Installed", "Prerequisite")

    ## EXECUTE ACTIONS

    Write-Message "Executing manifest plan (installing/updating software)..." "INFO"

    # Run appropriate manager action method for each package
    $plan | ForEach-Object {

        # Build action method name from package data and execute
        & "$([action].GetEnumName($_.Action))-Package" $_ | Out-Null

        # TODO: Find more generic solution.....
        if ( "$($_.Alias)" -eq "powershell") {
            Test-PowerShellVersion
        }

    }

    ## SAVE INVENTORY

    # Print updated manifest
    Show-Collection $inventory -Exclude @("Urls", "Sort", "Prerequisite", "Dependencies", "Action", "Selected", "Installed")

    # Prepare inventory list for export to file
    $inventoryFile = $global:inventory | Select-Object -ExcludeProperty Installed,Urls,Dependencies,Action,Sort,Selected | Sort-Object -Property Name

    # Save inventory to file
    Export-ToJsonFile $inventoryFile "inventory"

    Write-Message "Package orchestrator finished." "INFO"

}

#endregion


#region Version Handling

function Get-Version {
    param (
        [string] $rawVersion
    )

    if ( ( $rawVersion -match '\d+(\.\d+){0,2}' ) ) {

        return $matches[0]

    } else {

        Write-Warning "Could not extract a valid version number (${rawVersion})."

        return $null

    }

}


function Compare-Versions {
    param (
        [string] $versionOne,
        [string] $versionTwo
    )

    # Helper function to parse version numbers
    function Search-Version {
        param ([string]$version)

        $parsedVersion = New-Object int[] 3
        $versionParts = $version -split '\.'

        for ($i = 0; $i -lt 3; $i++) {
            $parsedVersion[$i] = if ($i -lt $versionParts.Count) { [int]$versionParts[$i] } else { 0 }
        }
        return $parsedVersion
    }

    $parsedVersionOne = Search-Version -version $versionOne
    $parsedVersionTwo = Search-Version -version $versionTwo

    for ($i = 0; $i -lt 3; $i++) {

        if ($parsedVersionOne[$i] -gt $parsedVersionTwo[$i]) {

            return $true

        } elseif ($parsedVersionOne[$i] -lt $parsedVersionTwo[$i]) {

            return $false

        }

    }

    return $false

}

#endregion


#region: Import / Export

function Export-ToJsonFile {
    param (
        [PSObject] $objectList,
        [string] $name
    )

    try {

        # Convert the object list to JSON format
        $jsonData = $objectList | ConvertTo-Json

    } catch {

        # Handle any errors that occur during the conversion to JSON
        Write-Message "Could not save content. Failed to convert object list to JSON -> ($($_.Exception.Message))" "WARNING"

        return

    }

    # Specify the path for the JSON file
    $jsonFilePath = (Join-Path $PSScriptRoot "${name}.json")

    # Log the attempt to save the JSON data
    Write-Message "Saving JSON content to '$jsonFilePath'..." "DEBUG"

    try {

        # Save the JSON data to the file
        $jsonData | Set-Content -Path $jsonFilePath -Force

    } catch {

        # Handle any errors that occur during the file writing process
        Write-Message "Failed to save JSON content to '$jsonFilePath'. $($_.Exception.Message)" "ERROR"

        return
    }

}


function Import-FromJsonFile {
    param (
        [string] $name
    )

    # Construct the full path to the JSON file
    $jsonFilePath = (Join-Path $PSScriptRoot "${name}.json")

    # Log the attempt to import the file
    Write-Message "Importing content from '$jsonFilePath'..." "DEBUG"

    # Check if the file exists before proceeding
    if (-not (Test-Path $jsonFilePath)) {

        # If the file doesn't exist, log an error and exit the function
        Write-Message "The file '$jsonFilePath' does not exist." "ERROR"

        return $null

    }

    try {

        # Read the content of the file and convert it from JSON format
        $content = Get-Content -Path $jsonFilePath -Raw | ConvertFrom-Json

    } catch {

        # Handle any errors that occur during JSON conversion
        Write-Message "Failed to parse JSON content from '$jsonFilePath' -> ($($_.Exception.Message)" "ERROR"

        return $null

    }

    # Return the parsed content
    return $content

}

#endregion


#region: Inventory Handling

function Update-InventoryAliasById {
    param (
        [Software] $item,
        [int] $index=0
    )

    # Check for package in inventory and update
    $global:inventory | ForEach-Object {

        # Compare current inventory entry with package ID
        if ($_.package[$index].Id -eq $item.package[$index].Id) {

            Write-Message "Updating package entry in inventory with alias from manifest ($($item.Alias))..." "DEBUG"

            # Update alias
            $_.Alias = $item.Alias

            return $True

        }

    }

    Write-Message "Package with ID '$($item.package[$index].Id)' not found in inventory." "DEBUG"

    return $False

}


function Add-ToInventory {
    param (
        [Software] $item,
        [int] $index=0
    )

    Write-Message "Updating package inventory with installed package '$($item.package[$index].Id)'..." "DEBUG"

    try {

        # Add package to inventory if not already included
        if ( -not ( $global:inventory | Where-Object { $_.package[$index].Id -eq $item.package[$index].Id } ) ) {

            # Add the package to the inventory list
            $global:inventory += @($item)

        } else {

            Write-Message "Package already present in inventory." "DEBUG"

        }

    }
    catch {

        Write-Message "Issues with adding package to inventory -> ($($_.Exception.Message))" "WARNING"

    }

}


function Test-Dependency {
    param (
        [array] $dependencies
    )

    # Initialize array for missing dependencies
    $local:missingDependencies = @()

    # Check if any dependencies to check
    if ( $item.Dependencies ) {

        Write-Message "Checking for dependencies in inventory ($($dependencies))..." "DEBUG"

        # Check each dependency package id
        ForEach ( $dependency in $dependencies) {

            Write-Message "Searching for dependency ($($dependency))..." "DEBUG"

            # Find the package with the specified id
            $dependencyPackage = $global:inventory | Where-Object { $_.Alias -eq $dependency }

            # Check if the dependency was found and flagged as installed
            if ( -not $dependencyPackage) {

                # Add to missing dependencies
                $missingDependencies += $dependency

            }

        }

    }

    return $missingDependencies

}

#endregion


#region: Package Handlers

function Find-Packages {
    param (
        [string]$packageManager
    )

    $idFilter =   @('MSIX', 'HP','km-', 'Intel', 'Printer','{')
    $nameFilter = @('Citrix')

    Write-Message "Finding installed packages ($($packageManager))..." "INFO"

    try {

        # Retrieve installed packages based for package manager
        switch ($packageManager) {

            "psrget" {

                $installedPackages = Get-InstalledPSResource
                $getAvailableVersion = { (Find-PSResource $installedPackage.Name -ErrorAction SilentlyContinue).Version }

            }
            "scoop" {

                $installedPackages = scoop list 6> $null
                $getAvailableVersion = { (scoop info $package.Id 6> $null).Version }

            }
            "winget" {

                $installedPackages = Get-WinGetPackage
                $getAvailableVersion = { ($installedPackage.AvailableVersions[0]) }

            }
            default {

                Write-Warning "Unknown package manager: $packageManager"
                return @()

            }

        }

        # Apply filtering to exclude packages with certain substrings in Id or Name
        $filteredPackages = $installedPackages | Where-Object {

                ( -not ( $_.Id -match [string]::Join('|', $idFilter) ) ) -and
                ( -not ( $_.Name -match [string]::Join('|', $nameFilter) ) )

        }


        # Create package objects for filtered packages
        $filteredPackages | ForEach-Object {

            $installedSoftware = Build-PackageDetails -packageManager $packageManager -installedPackage $_ -getAvailableVersion $getAvailableVersion

            if ( $installedSoftware ) { Add-ToInventory $installedSoftware }

        }

    }
    catch {

        Write-Message "Could not get installed packages ($($packageManager)): $($_.Exception.Message)" "ERROR"

    }

}


function Get-Package {
    param (
        [Software] $item,
        [int] $index=0
    )

    Write-Message "Checking software status and updating details ($($item.package[$index].Manager) / $($item.Alias))..." "DEBUG"

    # Initialize values
    $installedPackage = $null
    $packageAvailable = $null

    try {

        # Switch based on the manager type to handle different package managers
        switch ($item.package[$index].Manager) {

            "psrget" {

                # Handle PSResourceGet package manager
                $installedPackage = Get-InstalledPSResource -Name $item.package[$index].Id -ErrorAction SilentlyContinue
                $packageAvailable = $(Find-PSResource $item.package[$index].Id).Version

            }
            "scoop" {

                # Handle Scoop package manager
                $installedPackage = scoop list $item.package[$index].Id 6> $null
                $packageAvailable = $(scoop info $item.package[$index].Id 6> $null).Version

            }
            "winget" {

                # Handle WinGet package manager
                $installedPackage = Get-WinGetPackage $item.package[$index].Id
                $installedPackage | Add-Member -MemberType NoteProperty -Name Version -Value $installedPackage.InstalledVersion
                $packageAvailable = $(Find-WinGetPackage -Id $item.package[$index].Id).Version

            }
            "custom" {

                # Handle Custom package manager
                $fullFilePath = (Join-Path $PSScriptRoot "$($item.Alias)/setup.ps1")

                # Test file path and run custom methods
                if (Test-Path $fullFilePath -PathType Leaf) {

                     # Run custom script if available
                    . $fullFilePath

                    # Check installation status and get version
                    if ( & "Test-$($item.Name)" ) {

                        $installedPackage = [PSCustomObject]@{

                            Version = & "Get-$($item.Name)"

                        }

                    }

                    # Get available version for custom package
                    $packageAvailable = & "Get-$($item.Name)Available"

                } else {

                    # Handle missing file path
                    throw "The file '$fullFilePath' does not exist"

                }

            }
            default {

                # Handle unknown package manager
                throw "Unknown package manager '$($item.package[$index].Manager)'"

            }

        }

    } catch {

         # Handle any errors that occur during the process
        Write-Message "Error getting package details for '$($item.package[$index].Id)' -> ($($_.Exception.Message))" "WARNING"

        return

    }

    # If the package is installed, update the package details
    if ( $installedPackage ) {

        # Update details
        $item.Version = Get-Version $installedPackage.Version
        $item.Installed = $True
        $item.Action=[action]::None

        # Update inventory if the package is installed but not in inventory
        if ( -not (Update-InventoryAliasById $item ) ) {

            # Add as new entry to inventory if installed, but not in inventory.
            # Should only happen for Custom packages.
            Add-ToInventory $item

        }

    } else {

        # If not installed, mark the package for installation
        $item.Action = [action]::Install

    }

    # If available version is found, compare with the installed version
    if ( $packageAvailable ) {

        $item.Available = Get-Version $packageAvailable

        # Check that we have valid version numbers
        if ($item.Version -and $item.Available) {

            # Check if the installed version is the same as the available one
            if (Compare-Versions $item.Available $item.Version -and $item.Installed) {

                # If newer version available, mark the package for update
                $item.Action = [action]::Update

            }

        }

    }

}


function Install-Package {
    param (
        [Software]$item
    )

    $index = $item.Selected

    Write-Message "Installing software package ($($item.package[$index].Manager) / $($item.Alias))..." "DEBUG"

    try {

        # Check for missing dependencies
        if ( $missingDependencies = (Test-Dependency $item.Dependencies) ) {

            # Handle missing dependencies
            throw "Missing dependencies (${missingDependencies})"

        }

        # Switch based on the manager type to handle different package managers
        switch ($item.package[$index].Manager) {

            "psrget" {

                # Install package with PSResourceGet
                $result = $( Install-PSResource -Name $item.package[$index].id -NoClobber -AcceptLicense -PassThru -ErrorAction Stop )

                # Check result from install
                if ( $result ) { $success = $true } else { $success = $false }

            }
            "scoop" {

                # Install package with Scoop
                $result = $( scoop install $item.package[$index].id 6>&1 )

                # Check result from install
                if ( $( $result | Out-String ).Contains("successfully") ) { $success = $true } else { $success = $false }

            }
            "winget" {

                # Install package with WinGet
                $result = $( Install-WinGetPackage $item.package[$index].id )

                # Check result from install
                if ( $result.Succeeded() ) { $success = $true } else { $success = $false }

            }
            "custom" {

                # Assuming custom packages have specific scripts or executables to install
                $installScript = Join-Path $PSScriptRoot "$($item.Alias)/setup.ps1"

                # Test file path and run custom methods
                if (Test-Path $installScript -PathType Leaf) {

                    # Dot source the script to bring in the functions
                    . $installScript

                    # Install package using custom install script
                    $result = $( & "Install-$($item.Name)" 2>&1 )

                    if ("${result}" -eq "Reboot") {

                        Restart-ComputerAndContinue

                        Write-Message "Installation of '$($item.alias)' will continue on script startup after reboot." "INFO"

                        return $false

                    }

                    $success = $result

                } else {

                    # Handle missing file path
                    throw "The file '$fullFilePath' does not exist"

                }

            }
            default {

                # Handle unknown package manager
                throw "Unknown package manager '$($item.package[$index].Manager)'"

            }

        }

        # Check if install was successful
        if ( $success ) {

            # Try to get installed package details (updates Installed flag)
            Get-Package $item

            # Check if actually installed
            if ( $item.Installed ) {

                # Compare installed version with available
                if ( $item.Version -eq $item.Available ) {

                    Write-Message "Package successfully installed ($($item.Alias) / $($item.package[$index].Id))." "DEBUG"

                } else {


                    Write-Message "Potential package install issue (could not find installed version $($package.Available)). Computer or application might need to be restarted." "WARNING"

                }

                # Update PATH variable
                Update-Path

            } else {

                # Handle unconfirmed install
                throw "Could not get confirm that package was installed"

            }

        } else {

            # Handled failed install
            throw "Install method failed"

        }


    }
    catch {

        # Handle any errors that occur during the process
        Write-Message "Failed to install '$($item.package[$index].Id)' using '$($item.package[$index].Manager)' -> ($($_.Exception.Message))" "WARNING"

        return $false

    }

    return $true

}


function Update-Package {
    param (
        [Software] $item
    )

    $index = $item.Selected

    Write-Message "Updating software package ($($item.package[$index].Manager) / $($item.Alias))..." "DEBUG"

    try {

        # Switch based on the manager type to handle different package managers
        switch ($item.package[$index].Manager) {

            "psrget" {

                # Install package with PSResourceGet
                $result = $( Update-PSResource -Name $item.package[$index].id -NoClobber -AcceptLicense -PassThru -ErrorAction Stop)

                # Check result from install
                if ( $result ) { $success = $true } else { $success = $false }

            }
            "scoop" {

                # Install package with Scoop
                $result = $( scoop update $item.package[$index].id --quiet 6>&1 )

                # Check result from install
                if ( $( $result | Out-String ).Contains("ERROR") ) { $success = $true } else { $success = $false }

            }
            "winget" {

                # Check if update is available
                if ( $( Get-WinGetPackage $package.id ).IsUpdateAvailable ) {

                    # Install package with winget
                    $result = $( Update-WinGetPackage $item.package[$index].id )

                    # Check result from install
                    if ( $result.Succeeded() ) { $success = $true } else { $success = $false }

                } else {

                    Write-Message "No update available (check plan requesting update to $($item.available))." "WARNING"

                }

            }
            "custom" {

                # Assuming custom packages have specific scripts or executables to install
                $installScript = Join-Path $PSScriptRoot "$($item.Alias)/setup.ps1"

                # Test file path and run custom methods
                if (Test-Path $installScript -PathType Leaf) {

                    # Dot source the script to bring in the functions
                    . $installScript

                    # Install package using custom install script
                    $result = $( & "Update-$($item.Name)" 2>&1 )

                    $success = $result

                } else {

                    # Handle missing file path
                    throw "The file '$fullFilePath' does not exist"

                }

            }
            default {

                # Handle unknown package manager
                throw "Unknown package manager '$($item.package[$index].Manager)'"

            }

        }

        # Check if install was successful
        if ( $success ) {

            # Try to get installed package details (updates Installed flag)
            Get-Package $item

            # Check if actually installed
            if ( $item.Installed ) {

                # Compare installed version with available
                if ( $item.Version -eq $item.Available ) {

                    Write-Message "Package successfully updated from $($package.version) to $($package.available)." "DEBUG"

                } else {

                    Write-Message "Potential package update issue (installed version is ${versionInstalled}, not $($package.available)). Computer or application might need to be restarted." "WARNING"

                }

            } else {

                # Handle unconfirmed install/update
                throw "Could not get confirm that package was updated"

            }

        } else {

            # Handled failed update
            throw "Update method failed"

        }

    }
    catch {

        # Handle any errors that occur during the process
        Write-Message "Failed to install '$($item.package[$index].Id)' using '$($item.package[$index].Manager)' -> ($($_.Exception.Message))" "WARNING"

        return $false

    }

    return $true

}


function Build-PackageDetails {
    param (
        [string] $manager,
        [object] $installedPackage,
        [scriptblock] $getAvailableVersion
    )

    try {

        $software = [Software]::new()

        $software.Name               = $installedPackage.Name
        $software.Version            = $installedPackage.Version
        $software.Available          = (& $getAvailableVersion)
        $software.Installed          = $true
        $software.Selected           = 0

        $software.package[0].Manager = $manager
        $software.package[0].Id      = if ( $installedPackage.Id ) { $installedPackage.Id } else { $installedPackage.Name }
        $software.package[0].Source  = if ( $installedPackage.Repository ) { $installedPackage.Repository } else { $installedPackage.Source }

        return $software

    }
    catch {

        Write-Message "Problem with building package details." "WARNING"

        return $null

    }

}

#endregion


#region: Environment Functions

function Update-Path {

    # Refresh the PATH variable in the current session (in order for the 'git' command to work)
    $Env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")

}


function Restart-ComputerAndContinue {

    Write-Host "Continuing the setup process requires computer to be restarted."

    # Prompt the user for confirmation
    $confirmation = Read-Host "Do you want to restart the computer now? (Y/N)"

    Write-Host "A scheduled task will be created to restart the script on startup."

    if ( -not (Set-ScriptToRunAtStartup -delayMinutes 1) ) {

        Write-Host "Failed to create scheduled task. Creating shortcut instead."
        Write-Host "Please restart the script from the shortcut after computer has restarted."

        Build-ScriptShortcut | Out-Null

    }

    if ($confirmation -eq 'Y' -or $confirmation -eq 'y') {

        Write-Message "Restarting now..." "INFO"

        # Perform a graceful reboot
        Restart-Computer -Force

        exit 0

    } else {

        Write-Message "Reboot cancelled." "INFO"

    }

}


function Set-ScriptToRunAtStartup {
    param (
        [int]$delayMinutes = 1,
        [string[]]$scriptArguments = @()
    )

    Write-Message "Creating new Scheduled-Task for script to run at startup login..." "INFO"

    # Script Full Path
    $scriptPath = Join-Path $PSScriptRoot "orchestrator.ps1"

    # Set path for older PowerShell executable
    $oldPowerShellExecutablePath = "$Env:SYSTEMROOT\System32\WindowsPowerShell\v1.0\powershell.exe"

    # Task name
    $taskName = "SystemSetupOrchestrator"

    # Task folder
    $taskFolder = "User"

    # Get task user
    $taskUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    # Determine the PowerShell executable path
    $powerShellPath = Get-NewPowerShellPath

    # Check if new PowerShell installed
    if (-not $powerShellPath) {

        # Default to PowerShell 5.1 if PowerShell 7 is not found
        $powerShellPath = $oldPowerShellExecutablePath

    }

    # Check if the task already exists
    $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath "\$taskFolder" -ErrorAction SilentlyContinue

    # Create a new task if none was found
    if ( $null -eq $existingTask ) {

        try {

            # Convert script arguments array to a single string
            $argumentString = $scriptArguments -join ' '

            # Create an action to run the PowerShell script
            $Action = New-ScheduledTaskAction -Execute $powerShellPath -Argument "-NoExit -NoProfile -ExecutionPolicy RemoteSigned -File `"$scriptPath`" $argumentString"

            # Create a trigger to run the task at logon with a delay
            $Trigger = New-ScheduledTaskTrigger -AtLogOn -User $taskUser
            $Trigger.Delay = 'PT60S'

            # Create a principal to run the task with elevated (administrator) privileges
            $Principal = New-ScheduledTaskPrincipal -UserId "User" -LogonType Interactive -RunLevel Highest

            # Register the scheduled task with the administrator privileges
            Register-ScheduledTask -Action $Action -Trigger $Trigger -TaskName $TaskName -TaskPath "\$TaskFolder" -Principal $Principal -Force

            Write-Message "Scheduled task '$($taskName)' created successfully." "DEBUG"

            return $True

        } catch {

            Write-Message "Could not create scheduled task -> ($($_.Exception.Message))" "ERROR"

            return $False

        }

    } else {

        Write-Message "Scheduled task '$($taskName)' already exists. No action taken." "DEBUG"

        return $True

    }

}


function Remove-ScheduledTask {
    param (
        [string]$taskName
    )

    Write-Message "Removing scheduled task for the script..." "INFO"

    $taskName = "SystemSetupOrchestrator"

    $taskFolder = "\User\"

    # Check if the task exists
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

    if ($null -ne $existingTask) {

        # Remove the scheduled task
        Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskFolder -Confirm:$false

        # Check if the task exists
        $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

        if ($null -ne $existingTask) {

            Write-Message "Failed to remove '$($taskName)' in folder '$($taskFolder)'." "WARNING"

        } else {

            Write-Message "Scheduled task '$($taskName)' in folder '$($taskFolder)' removed successfully." "INFO"

        }

    } else {

        Write-Message "Scheduled task '$($taskName)' in folder '$($taskFolder)' does not exist. No action taken." "DEBUG"

    }

}


function Test-AdminPrivileges {

    # Check if the current user has admin privileges
    $isAdmin = ([System.Security.Principal.WindowsPrincipal] [System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole] "Administrator")

    if (-not $isAdmin) {

        Write-Message "This script requires administrator privileges to run." "WARNING"
        Write-Message "Please restart PowerShell as administrator (right-click and select 'Run as Administrator') and run the script again." "WARNING"

        # Exit the script
        exit

    } else {

        Write-Message "Script is running with administrator privileges. Proceeding..." "DEBUG"
    }

}


function Test-PowerShellHost {

    # Check if running inside Windows Terminal
    $isWindowsTerminal = $Env:WT_SESSION

    if ($isWindowsTerminal) {

        Write-Message "This script is currently running in Windows Terminal which in some cases can cause issues." "WARNING"
        Write-Message "Creating a desktop shortcut to open the script in standalone PowerShell as admin..." "INFO"

        if ( Build-ScriptShortcut ) {

            Write-Message "Please use the shortcut to run this script in a standalone PowerShell console as admin." "INFO"

        } else {

            Write-Message "Please start the script again from a standalone Powershell condole running as admin." "INFO"

        }

        Write-Message "You can now close this session..." "INFO"

        # Exit the script
        exit

    } else {

        Write-Message "Running in a standalone PowerShell console. Proceeding with the script..." "INFO"

    }

}


function Test-PowerShellVersion {

    Write-Message "Checking PowerShell version..." "INFO"

    # Check if we are already running in PowerShell 7+
    if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {

        # Get PowerShell version
        $currentPowershell = $PSVersionTable.PSVersion.ToString()

        Write-Message "Script is running in PowerShell (${currentPowershell})." "INFO"
        Write-Message "Checking if PowerShell 7 is available..." "INFO"

        # Find PowerShell 7 executable
        $pwsh = Get-NewPowerShellPath

        # Restart in new shell if PowerShell 7 found.
        if ($pwsh) {

            Write-Message "PowerShell 7 found. Restarting in new shell..." "INFO"

            # Restart the script in PowerShell 7
            Start-Process -FilePath "pwsh" -ArgumentList "-NoExit -NoProfile -ExecutionPolicy RemoteSigned -File `"$PSCommandPath`" @args"

            Start-Sleep -Milliseconds 500

            # Exit the current session to avoid duplicate runs
            Stop-Process -Id $PID -force

        } else {

            Write-Message "PowerShell 7 is not yet installed. Continuing..." "DEBUG"

        }

    } else {

        Write-Message "Script is running in PowerShell 7. Continuing..." "DEBUG"

    }

}


function Get-NewPowerShellPath {

    # Define common installation paths for PowerShell 7
    $pwshPaths = @(
        "$Env:ProgramFiles\PowerShell\7\pwsh.exe",    # Default installation path for PowerShell 7
        "$Env:ProgramFiles\PowerShell\pwsh.exe",      # Alternative location
        "C:\Program Files\PowerShell\7\pwsh.exe"      # Explicit path for common installations
    )

    # Find and return the PowerShell 7 executable path, or null if not found
    return $pwshPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

}


function Build-ScriptShortcut {

    # Get PowerShell 7 path if installed
    $newPowershellPath = Get-NewPowerShellPath

    # Check of PowerShell 7 path was found
    if ( $newPowershellPath ) {

        # Get path for PowerShell 7 executable
        $powerShellPath = $newPowershellPath

    } else {

        # Define the path for the PowerShell 5.1 executable
        $powerShellPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    }

    try {

        # Define the path for the shortcut
        $desktopPath = [System.Environment]::GetFolderPath("Desktop")
        $shortcutPath = Join-Path -Path $desktopPath -ChildPath "Package Installer.lnk"

        # Create the WScript.Shell COM object
        $shell = New-Object -ComObject WScript.Shell

        # Create the shortcut
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $powerShellPath
        $shortcut.Arguments = "-NoExit -NoProfile -ExecutionPolicy RemoteSigned -File `"$($PSCommandPath)`""
        $shortcut.WorkingDirectory = (Get-Location).Path
        $shortcut.WindowStyle = 1
        $shortcut.IconLocation = "$powerShellPath,0"
        $shortcut.Description = "Windows packages installed shortcut"

        # Set the shortcut to run as administrator
        $shortcut.Save()

        # Set byte 21 (0x15) bit 6 (0x20) ON (sets the "Run as Administrator" flag by changing the bit)
        $bytes = [System.IO.File]::ReadAllBytes("$shortcutPath")
        $bytes[0x15] = $bytes[0x15] -bor 0x20
        [System.IO.File]::WriteAllBytes("$shortcutPath", $bytes)
        [System.IO.File]::SetAttributes($shortcutPath, 'ReadOnly')

    }
    catch {

        Write-Message "Failed to create shortcut. You might need to restart the script from command line if required." "WARNING"

        return $false

    }

    Write-Message "Shortcut created on the desktop ($($shortcutPath))." "WARNING"

    return $true

}

#endregion


function ConvertTo-Class {
    param (
        [object]$SourceObject,
        [Type]$TargetType
    )

    # Create a new instance of the target class using reflection
    $targetInstance = [Activator]::CreateInstance($TargetType)

    # Iterate over the properties of the target class to map values from the source object
    foreach ($property in $TargetType.GetProperties()) {

        $propertyName = $property.Name

        # Check if the source object has a matching property to map to the target class
        if ($SourceObject.PSObject.Properties[$propertyName]) {

            # If the property is an array of Package objects, handle it separately
            if ($property.PropertyType.IsArray -and $property.PropertyType.GetElementType() -eq [Package]) {

                $packageArray = @()  # Initialize an empty array to hold Package objects

                # Iterate over each item in the source object's array (assumed to be a list of packages)
                foreach ($pkg in $SourceObject.$propertyName) {

                    # Recursively map each package in the array to a Package object
                    $packageInstance = ConvertTo-Class -SourceObject $pkg -TargetType ([Package])
                    $packageArray += $packageInstance

                }

                # Explicitly cast the array to Package[] type before setting it on the target property
                $property.SetValue($targetInstance, [Package[]]$packageArray)

            }

            # For string arrays (string[]) properties, cast to string[] explicitly
            elseif ($property.PropertyType -eq [string[]]) {

                $stringArray = [string[]]$SourceObject.$propertyName
                $property.SetValue($targetInstance, $stringArray)

            }

            # For simple properties (e.g., string, bool), assign the value directly
            elseif ($property.PropertyType.IsValueType -or $property.PropertyType -eq [string]) {

                # Set the value of the property in the target instance
                $property.SetValue($targetInstance, $SourceObject.$propertyName)

            }

        }

    }

    # Return the populated instance of the target class
    return $targetInstance

}



Test-PowerShellHost


Test-AdminPrivileges


Test-PowerShellVersion


Start-PackageOrchestrator
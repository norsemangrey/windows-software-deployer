# PowerShell Script for Workstation Setup

## Overview

This is a personal project created to automate the setup of a Windows 11 workstation or development environment after a fresh install. It aims to make the process of installing and configuring software I mostly always use straightforward and flexible. The script uses a manifest-driven approach, which means you can easily customize what gets installed and how. It supports common package managers and allows for custom installation scripts when needed. The goal is to save time and reduce manual effort during setup, while still being reusable and adaptable to different needs.

- A generic and modular framework for installing software using a manifest.
- Makes use of common Windows package managers (e.g., PSResourceGet, Winget, Scoop).
- Support for custom installer scripts to handle more specialized installation procedures.
- Automatic installation of prerequisite packages to prepare the system.
- Stateless execution, enabling it to add or update software at any time without disrupting the environment.
- Reboot-and-continue capability for installations requiring system reboots.

## Features

1. **Manifest-Driven Installation**:

   - The manifest defines the software to install, including dependencies.
   - Prerequisites are installed first, ensuring all required package managers and tools are available.

2. **Stateless Execution**:

   - Can be run repeatedly without disrupting the current state.
   - Creates and maintains an inventory of installed software.

3. **Privilege and Compatibility Checks**:

   - Verifies administrative privileges and PowerShell version to prevent issues with package managers.

4. **Custom Package Support**:

   - Allows installation of software not available through standard package managers using custom scripts.

## Requirements/Target System

- **Operating System:** Windows 11

- **Prerequisites:**

  - PowerShell (at least 5.1)
  - Winget (there are some provisions for installing Winget aimed for W10, but this has issues)
  - Administrator privileges
  - Internet connection for downloading packages


## Usage Instructions

1. Ensure PowerShell is running with administrative privileges.
2. Clone or download the repo to your workstation.

   You can download and run the main script directly using the following command:

   ```powershell
   & ([scriptblock]::Create($(Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/norsemangrey/powershell-script-support-functions/main/download-and-run.ps1'))) -user 'norsemangrey' -repo 'windows-software-deployer' -branch 'main' -script 'orchestrator.ps1'
    ```

3. Update the manifest file to include the desired software and dependencies.
4. Run the script:

   ```powershell
   .\orchestrator.ps1
    ```

## Structure

### Environment

First the script will do some checking and handling of admin privileges as well as PowerShell version in order to avoid some potential issues with the package managers.

### Manifest

The script will install/update software based on the current inventory and the content of the `manifest.json` file. Entries in the manifest follow this structure:

```json
{
    "name": "<custom-name>",
    "alias": "<custom-alias>",
    "urls": [
        "<url-to-software-website-etc>"
    ],
    "package": {
        "manager": "<package-manager>",
        "id": "<manager-package-id>"
    },
    "dependencies": [<alias-1>,<alias-2>],
    "targets": [
        "windows"
    ],
    "prerequisite": false
}
```

#### Field Details

- **name**: A descriptive name for the package.
- **alias**: A unique identifier for the package.
- **urls**: Links to the software's website or documentation (optional).
- **package**:
  - **manager**: The package manager to use ("psrget", "winget", "scoop", "custom").
  - **id**: The package ID as registered with the specified package manager.
- **dependencies**: Aliases of other packages that must/should be installed first.
- **targets**: Currently supports "Windows" only (WSL is in the thoughts).
- **prerequisite**: Set this to `false` (use to identify the managers that must be available prior to installing additional packages)

### Custom Packages

Custom packages are those not available via standard package managers or requiring additional setup. To handle custom packages:

1. Create a `setup.ps1` script in a subfolder named after the package alias.
2. Implement the following methods in the `setup.ps1` script:

#### Required Methods

The script will handle the check, installation and update of the custom packages as long as the methods are defined in a script under a subfolder with the name of the package alias. A set of methods must be defined for the main script to interact with (calling indirectly using the package alias) that follows a set naming and output:

- **`Test-<Alias>`**

  - **Purpose**: Checks if the package is installed by querying its version.
  - **Output**: Returns `$True` if installed, `$False` otherwise.

- **`Get-<Alias>`**

  - **Purpose**: Retrieves the currently installed version of the package.
  - **Output**: The installed version or `$Null` if not installed.

- **`Get-Available<Alias>`**

  - **Purpose**: Retrieves the latest available version of the package.
  - **Output**: The latest available version or `$Null` if not found.

- **`Install-<Alias>`**

  - **Purpose**: Installs the package if it's not already installed.
  - **Output**: Returns `$True` if successful, throws an error and returns `$False` otherwise.

- **`Update-<Alias>`**

  - **Purpose**: Updates the package to the latest version.
  - **Output**: Returns `$True` if successful, `$False` otherwise.

### Stateless

The script is meant to be stateless so that it can run at any point also after initial install (adding additional- or updating existing packages) without messing things up. It will use the installed managers and helpers to check the current installed software and create an inventory (`inventory.json`) which will be continuously updated as the script progresses checking- and installing software as pr. the manifest.

### Reboot Handling

- Sets up a scheduled task to resume the script automatically after a reboot.

- Primarily used for WSL setup but can handle other scenarios as well.

### Logging

- Generates detailed logs to help you track progress and debug any issues.

- Review these logs after running the script to ensure everything went smoothly.


## Execution Flow

1. **Initial Checks**: Ensures all prerequisites like PowerShell version and admin rights are met.

2. **Import Manifest**: Loads the manifest.json file for processing.

3. **Check and Install Prerequisites**: Verifies that all required package managers and other necessary tools are installed.

4. **Build Initial Inventory**: Uses the installed package managers to create a snapshot of currently installed software.

5. **Check Packages in Manifest**: Compares the manifest entries with the inventory to identify missing or outdated packages.

6. **Create a Plan**: Generates an actionable plan based on the checks, including install or upgrade tasks.

7. **Sort Plan by Dependencies**: Orders the plan topologically to ensure dependencies are installed first.

8. **Execute Plan**: Processes each task in the plan by:
   - Using install and upgrade methods that invoke package manager commands or custom script methods.
   - Continuously updating the inventory to reflect completed tasks.

9.  **Save Inventory**: Writes the updated inventory to a file when the process is complete.


## Notes

- Prerequisite packages defined in the manifest should remain unchanged to ensure proper functionality.
- The script currently supports Windows (11) environments only.
- For troubleshooting, review logs generated during script execution.


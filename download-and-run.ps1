# Variables to configure at the beginning of the script
$githubUsername = "norsemangrey"
$repositoryName = "windows-software-deployer"
$branchName = "main"
$scriptFilePath = "orchestrator.ps1"

# URL to download the entire repository as a ZIP file
$repoUrl = "https://github.com/$githubUsername/$repositoryName/archive/refs/heads/$branchName.zip"

# Path to save the ZIP file locally
$zipFilePath = "$env:TEMP\$repositoryName.zip"

# Download the ZIP file
Invoke-WebRequest -Uri $repoUrl -OutFile $zipFilePath

# Extract the ZIP file to a temporary directory
$extractPath = "$env:TEMP\$repositoryName"
Expand-Archive -Path $zipFilePath -DestinationPath $extractPath

# Path to the script you want to run (relative to the root of the extracted folder)
$scriptPath = "$extractPath\$repositoryName-$branchName\$scriptFilePath"

# Run the script
& $scriptPath
<#
.SYNOPSIS
    Downloads AzCopy v10 from Microsoft and installs it to C:\AzCopy.
#>
[CmdletBinding()]
param(
    [string]$InstallPath = 'C:\AzCopy'
)

$ErrorActionPreference = 'Stop'
$zip = Join-Path $env:TEMP 'azcopy.zip'
$tmp = Join-Path $env:TEMP 'azcopy'

# Create the target folder (-Force: no error if it already exists)
New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null

# Download the latest AzCopy v10 for Windows from Microsoft's official link
Invoke-WebRequest -Uri 'https://aka.ms/downloadazcopy-v10-windows' -OutFile $zip

# Extract the ZIP and copy azcopy.exe to the install folder
Expand-Archive -Path $zip -DestinationPath $tmp -Force
Get-ChildItem $tmp -Recurse -Filter 'azcopy.exe' |
    Select-Object -First 1 |
    Copy-Item -Destination $InstallPath -Force

# Clean up temporary files
Remove-Item $zip, $tmp -Recurse -Force

# Show the installed version
& (Join-Path $InstallPath 'azcopy.exe') --version

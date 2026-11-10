<#
.SYNOPSIS
    Uploads all files in a folder to an Azure Blob Storage container with AzCopy.

.DESCRIPTION
    - Checks that AzCopy and the source files exist.
    - Asks for the SAS token as a secure input, so it is not stored in the
      script, the PowerShell history or a screenshot.
    - Supports -WhatIf to show what would be uploaded.

.EXAMPLE
    .\Upload-BackupToAzure.ps1 -SourcePath "D:\Backups\ToUpload" -StorageAccount "<storage-account>" -Container "weekly-backups" -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string]$SourcePath,
    [Parameter(Mandatory)] [string]$StorageAccount,
    [Parameter(Mandatory)] [string]$Container,
    [string]$AzCopyPath = 'C:\AzCopy\azcopy.exe'
)

$ErrorActionPreference = 'Stop'

# 1. Check prerequisites
if (-not (Test-Path $AzCopyPath)) { throw "AzCopy not found at $AzCopyPath. Run Install-AzCopy.ps1 first." }
if (-not (Test-Path $SourcePath)) { throw "Source folder not found: $SourcePath" }

$files = @(Get-ChildItem $SourcePath -File -Recurse)
if ($files.Count -eq 0) { throw "No files found in $SourcePath" }

$totalGB = [math]::Round(($files | Measure-Object Length -Sum).Sum / 1GB, 1)
Write-Host "Files to upload: $($files.Count) ($totalGB GB)" -ForegroundColor Cyan
$files | ForEach-Object { Write-Host ("  {0}  {1:N1} GB" -f $_.Name, ($_.Length / 1GB)) }

# 2. Dry run ends here
$target = "https://$StorageAccount.blob.core.windows.net/$Container"
if (-not $PSCmdlet.ShouldProcess($target, "Upload $($files.Count) file(s)")) { return }

# 3. Ask for the SAS token securely (the part after the '?')
$secure = Read-Host 'Paste the SAS token (starts with sv= or sp=)' -AsSecureString
$sas = [System.Net.NetworkCredential]::new('', $secure).Password.TrimStart('?')
if ($sas -notmatch 'sp=[^&]*w') {
    Write-Warning 'The SAS token has no Write permission (sp=...w). The upload will fail with 403.'
}

# 4. Upload
& $AzCopyPath copy $SourcePath "$target`?$sas" --recursive
if ($LASTEXITCODE -ne 0) {
    throw "AzCopy failed (exit code $LASTEXITCODE). Resume with: azcopy jobs resume <job-id>"
}
Write-Host 'Upload completed. Verify the blob sizes in the Azure portal.' -ForegroundColor Green

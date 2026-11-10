# Weekly Backups to Azure Blob Storage with PowerShell and AzCopy

Moving large weekly application backups (~24 GB ZIP files) from SharePoint/OneDrive
to Azure Blob Storage, using PowerShell and AzCopy, with automatic retention and
least-privilege access.

> All names, IDs and paths in this repository are placeholders. No real
> company data, keys or SAS tokens are included.

## The problem

- An application produces one full backup per week as a ZIP file of about 24 GB.
- The backups were stored in SharePoint/OneDrive, which is not built for this:
  large files, no retention rules, and they use up collaboration storage.
- Uploading 24 GB through a browser is unreliable: one connection drop and the
  upload starts from zero.

## The solution

```
 Backup server / PC                     Azure (Germany West Central)
 ┌──────────────────────┐   HTTPS +    ┌──────────────────────────────────────┐
 │ Backup-YYYY-MM-DD.zip │ ── AzCopy ─► │ Storage account (StorageV2, RA-GRS)  │
 │   (PowerShell)        │   SAS token  │   └─ container: weekly-backups       │
 └──────────────────────┘              │       Cool tier · lifecycle 42 days  │
                                       │       soft delete 7 days             │
                                       └──────────────────────────────────────┘
```

| Setting | Value | Why |
| --- | --- | --- |
| Account kind | StorageV2, Standard | General purpose, supports lifecycle rules |
| Replication | RA-GRS | Copy in a second region, readable if the primary fails |
| Default access tier | Cool | Cheaper storage for data that is rarely read |
| Lifecycle rule | Delete blobs in `weekly-backups/` after 42 days | Keeps the last 6 weekly backups automatically |
| Blob / container soft delete | 7 days | Recover accidental deletions |
| Anonymous access | Disabled | No public access to backups |
| Minimum TLS / secure transfer | TLS 1.2 / HTTPS only | Encryption in transit |

The lifecycle rule is in [`lifecycle-policy.json`](lifecycle-policy.json).

## Why AzCopy instead of the portal upload

- **Resumable:** an interrupted 24 GB upload continues with `azcopy jobs resume`
  instead of starting over.
- **Fast:** uploads several blocks of a file in parallel.
- **Scriptable:** the same command can run weekly from Task Scheduler.

## How it works

### 1. Install AzCopy

[`scripts/Install-AzCopy.ps1`](scripts/Install-AzCopy.ps1) downloads AzCopy from
Microsoft's official link, extracts it and copies `azcopy.exe` to `C:\AzCopy`.

```powershell
.\scripts\Install-AzCopy.ps1
C:\AzCopy\azcopy.exe --version
```

### 2. Create a short-lived SAS token

In the Azure portal: container → **Shared access tokens**.

- Permissions: Read, Add, Create, Write, List (nothing more)
- Expiry: the same day, or at most 1–2 days
- Protocol: HTTPS only

A SAS token works like a password. It is never stored in a script, committed to
Git or shown in screenshots.

### 3. Upload

[`scripts/Upload-BackupToAzure.ps1`](scripts/Upload-BackupToAzure.ps1) checks the
source files, asks for the SAS token as a secure input and starts AzCopy.

```powershell
# Dry run: shows what would be uploaded
.\scripts\Upload-BackupToAzure.ps1 -SourcePath "D:\Backups\ToUpload" `
    -StorageAccount "<storage-account>" -Container "weekly-backups" -WhatIf

# Real upload
.\scripts\Upload-BackupToAzure.ps1 -SourcePath "D:\Backups\ToUpload" `
    -StorageAccount "<storage-account>" -Container "weekly-backups"
```

At ~28 Mbit/s, two backups (~50 GB) take about 4 hours. The machine must not go
to sleep during the upload:

```powershell
powercfg /change standby-timeout-ac 0    # disable sleep on AC power
powercfg /change standby-timeout-ac 30   # restore afterwards
```

### 4. Verify

- AzCopy ends with `Final Job Status: Completed`.
- In the portal, the blob sizes match the local file sizes byte for byte.

## Troubleshooting

| Error | Cause | Fix |
| --- | --- | --- |
| `403 AuthorizationPermissionMismatch` | SAS token is read-only (`sp=r`) | Create a new token with Write/Create permissions |
| `403 AuthenticationFailed` | SAS token expired | New token, then `azcopy jobs resume <id> --destination-sas "<token>"` |
| Upload stopped (sleep, network) | Connection lost | `azcopy jobs resume <id>` |
| File not found | OneDrive file is cloud-only | "Always keep on this device" before uploading |

## What I learned

- Designing storage for backups: access tiers, replication, lifecycle rules and
  soft delete, and how retention is calculated (from upload date, not backup date).
- Least-privilege access with SAS tokens, and why a leaked ad-hoc SAS can only be
  revoked by expiry or key rotation.
- PowerShell basics in practice: variables, environment variables, the pipeline,
  `-WhatIf` before changing anything, and reading error output.

## Next steps

- Run the upload weekly via Task Scheduler.
- Replace manual SAS tokens with a managed identity or service principal plus
  Azure RBAC (Storage Blob Data Contributor), so no token handling is needed.

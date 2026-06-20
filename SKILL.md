---
name: mobile-file-handoff
description: Package local files or folders and upload them to a temporary no-login file host for mobile download. Use when the user is away from the PC, says they are on mobile, asks to receive a zip/link, asks to upload generated artifacts, or needs a public temporary download URL for files in the workspace. Includes hash verification after upload and supports tmpfiles.org and Filebin fallbacks.
---

# Mobile File Handoff

Use this skill when the user needs access to local workspace files from a phone or another device.

## Workflow

1. Identify the file or folder to send. If the user does not specify one, use the most recent requested artifact or ask a short clarification.
2. If the target is a folder, package it as a zip. If the target is already a single file, upload it directly unless the user asked for a zip.
3. Run `scripts/upload-mobile-handoff.ps1` from this skill.
4. Return the first verified link and any backup verified links.
5. Mention expiry when known.

## Script

Use the bundled PowerShell script:

```powershell
& "$env:USERPROFILE\.codex\skills\mobile-file-handoff\scripts\upload-mobile-handoff.ps1" `
  -Path "C:\path\to\artifact-or-folder"
```

Useful options:

```powershell
# Force zip output even for a single file.
-Zip

# Choose output zip name when packaging a folder or forcing zip.
-ArchiveName "project-handoff.zip"

# Try only one provider.
-Provider tmpfiles
-Provider filebin

# Set tmpfiles expiry in seconds. Range supported by tmpfiles is usually 60 to 172800.
-TmpfilesExpireSeconds 172800
```

The script prints JSON containing:

- `localPath`
- `localSha256`
- `verifiedLinks`
- `failedProviders`

Only share URLs from `verifiedLinks`.

## Provider Notes

- Prefer `tmpfiles.org` because it returns a direct `/dl/` URL that works well on mobile.
- Use Filebin as a backup. Its standard share URL is `https://filebin.net/{bin}/{filename}`.
- Do not rely on `file.io` unless it starts accepting uploads again. It may redirect to `www.file.io` and reject API POST requests.
- Avoid upload services that return only an HTML landing page unless an actual download check confirms the file hash.

## Verification Rule

Never present a link as successful only because the upload API returned `200 OK`.

Always:

1. Download the link or direct-download variant.
2. Compare SHA-256 against the local file.
3. Return only links whose downloaded hash matches.

If no provider verifies, say that upload failed and include the provider errors.

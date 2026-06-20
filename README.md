# Mobile File Handoff

Mobile File Handoff is a Codex skill for getting local files from your
development machine onto a phone, tablet, or another device without setting up
cloud storage, email attachments, or a permanent file-sharing account.

It packages a local file or folder, uploads it to a temporary no-login file
host, downloads the uploaded file back, verifies the SHA-256 hash, and returns
only links that were proven to match the local artifact.

This is useful when you are developing from mobile, reviewing work away from
your desk, or need to attach a generated file somewhere through chat.

## What This Skill Solves

Codex often creates files locally: screenshots, PDFs, zips, app builds,
spreadsheets, logs, trace files, images, prototypes, and other artifacts. Those
files are easy to inspect on the development machine, but inconvenient when you
are on a phone or need to move the output into another app.

This skill gives Codex a repeatable handoff workflow:

1. Select the requested local artifact.
2. Zip folders automatically.
3. Upload to a temporary public file host.
4. Re-download the uploaded file.
5. Compare SHA-256 hashes.
6. Return verified mobile-friendly download links.

The important part is verification. A provider returning `200 OK` is not enough;
the skill only shares a URL after the downloaded bytes match the local file.

## Example Use Cases

- "I am on mobile, send me the zip."
- "Upload the generated PDF so I can attach it in WhatsApp."
- "Package the screenshots and give me a phone download link."
- "I need the build artifact from this workspace on my iPad."
- "Make a temporary link for this spreadsheet."
- "Send the current project folder as a zip."
- "I need to forward this report through chat, upload it for me."

## Repository Contents

```text
mobile-file-handoff/
|-- SKILL.md
|-- README.md
|-- agents/
|   `-- openai.yaml
`-- scripts/
    `-- upload-mobile-handoff.ps1
```

### `SKILL.md`

The Codex-facing instructions. This is intentionally concise so the agent can
load it quickly when the skill triggers.

### `agents/openai.yaml`

UI metadata for Codex skill listings, including display name, short
description, and default prompt.

### `scripts/upload-mobile-handoff.ps1`

The deterministic PowerShell helper that packages, uploads, verifies, and emits
JSON results.

## Installation

Clone or copy this folder into your Codex skills directory:

```powershell
git clone https://github.com/Tavaresiqueira/mobile-file-handoff.git `
  "$env:USERPROFILE\.codex\skills\mobile-file-handoff"
```

If you already cloned the repository somewhere else, copy it into the skill
directory:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.codex\skills" | Out-Null
Copy-Item -Recurse -Force `
  "C:\path\to\mobile-file-handoff" `
  "$env:USERPROFILE\.codex\skills\mobile-file-handoff"
```

Restart Codex after installing so the skill metadata is discovered.

## Using It Through Codex

Once installed, ask Codex naturally:

```text
Use mobile-file-handoff to send me the PDF you just created.
```

```text
I am on my phone. Zip the screenshots folder and give me a verified link.
```

```text
Upload the generated spreadsheet so I can attach it in another chat.
```

Codex should run the bundled script, inspect its JSON output, and return only
links listed under `verifiedLinks`.

## Direct Script Usage

You can also run the script yourself from PowerShell:

```powershell
& "$env:USERPROFILE\.codex\skills\mobile-file-handoff\scripts\upload-mobile-handoff.ps1" `
  -Path "C:\path\to\artifact-or-folder"
```

Upload one file directly:

```powershell
& ".\scripts\upload-mobile-handoff.ps1" `
  -Path ".\report.pdf"
```

Zip and upload a folder:

```powershell
& ".\scripts\upload-mobile-handoff.ps1" `
  -Path ".\screenshots"
```

Force a single file into a zip:

```powershell
& ".\scripts\upload-mobile-handoff.ps1" `
  -Path ".\report.pdf" `
  -Zip `
  -ArchiveName "report-handoff.zip"
```

Try only one provider:

```powershell
& ".\scripts\upload-mobile-handoff.ps1" `
  -Path ".\artifact.zip" `
  -Provider tmpfiles
```

Set a tmpfiles expiry:

```powershell
& ".\scripts\upload-mobile-handoff.ps1" `
  -Path ".\artifact.zip" `
  -TmpfilesExpireSeconds 172800
```

## Script Parameters

| Parameter | Required | Description |
| --- | --- | --- |
| `-Path` | Yes | File or folder to hand off. Folders are zipped automatically. |
| `-Zip` | No | Force zip packaging even when `-Path` points to one file. |
| `-ArchiveName` | No | Name for the generated zip when packaging is used. |
| `-Provider` | No | `all`, `tmpfiles`, or `filebin`. Defaults to `all`. |
| `-TmpfilesExpireSeconds` | No | Expiry for tmpfiles uploads. Defaults to `172800` seconds. |

## Output Format

The script prints JSON:

```json
{
  "localPath": "C:\\Users\\you\\AppData\\Local\\Temp\\screenshots-mobile-handoff.zip",
  "localSha256": "ABCD1234...",
  "verifiedLinks": [
    {
      "provider": "tmpfiles",
      "url": "https://tmpfiles.org/dl/example/file.zip",
      "pageUrl": "https://tmpfiles.org/example/file.zip",
      "expires": "up to 172800 seconds",
      "sha256": "ABCD1234..."
    }
  ],
  "failedProviders": []
}
```

Only share URLs from `verifiedLinks`.

If `failedProviders` contains entries, they are diagnostic information for
providers that failed upload or verification. A failure from one provider does
not matter when another provider produced a verified link.

## Providers

### tmpfiles.org

Preferred provider. It usually returns a page URL, and the script converts it to
the `/dl/` direct-download URL before verification.

### Filebin

Fallback provider. It returns a standard Filebin URL and an expiry timestamp
when available.

### Why Not `file.io`?

The skill avoids `file.io` because it has been observed redirecting API uploads
and rejecting POST requests. Providers should only be used when their uploaded
bytes can be downloaded and hash-verified.

## Security And Privacy

Temporary file hosts are public-link systems. Anyone with the URL may be able to
download the file until it expires or is deleted by the provider.

Use this skill for convenience artifacts, generated outputs, screenshots,
archives, and files you are comfortable sharing through a temporary public link.
Do not use it for secrets, production credentials, private keys, customer data,
unredacted financial records, or anything that requires access control.

The local SHA-256 hash is printed so Codex and the user can confirm that the
downloaded file matches the upload. The hash does not encrypt or protect the
file; it only verifies integrity.

## Troubleshooting

### No verified links returned

Check `failedProviders` in the JSON output. Common causes:

- The provider is temporarily unavailable.
- Network access is blocked.
- The file is too large for the provider.
- The provider returned an HTML page instead of the actual file.
- The verification download produced a different hash.

Try again later, reduce the file size, or run with a specific provider:

```powershell
& ".\scripts\upload-mobile-handoff.ps1" -Path ".\artifact.zip" -Provider filebin
```

### Folder upload did not include what you expected

Folders are zipped by compressing the folder contents. If you need the folder
itself as the top-level item inside the archive, create the zip yourself and
upload that zip as a single file.

### Link opens a provider page instead of downloading

Use the `url` field from `verifiedLinks`, not `pageUrl`. The `url` field is the
download URL that passed hash verification.

### Mobile browser says the file is unsafe

Some mobile browsers warn on downloaded archives from temporary hosts. If the
hash matches the local file and you trust the source artifact, the warning is a
browser/provider policy warning, not a hash verification failure.

## Development Notes

Validate the skill metadata after edits with the Codex skill validator when it
is available:

```powershell
python "$env:USERPROFILE\.codex\skills\.system\skill-creator\scripts\quick_validate.py" `
  "$PWD"
```

For script changes, test with a small disposable file before publishing:

```powershell
Set-Content -Path ".\handoff-test.txt" -Value "mobile handoff test"
& ".\scripts\upload-mobile-handoff.ps1" -Path ".\handoff-test.txt" -Provider tmpfiles
Remove-Item ".\handoff-test.txt"
```

Before returning a link to a user, keep the invariant strict: only URLs whose
downloaded content matches `localSha256` belong in the final answer.

## License

No license has been declared yet. Treat the code as private unless a license is
added by the repository owner.

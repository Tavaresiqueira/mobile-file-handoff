param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [switch]$Zip,

    [string]$ArchiveName,

    [ValidateSet("all", "tmpfiles", "filebin")]
    [string]$Provider = "all",

    [int]$TmpfilesExpireSeconds = 172800
)

$ErrorActionPreference = "Stop"

function New-TempArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [string]$Name
    )

    $resolved = Resolve-Path -LiteralPath $SourcePath
    $item = Get-Item -LiteralPath $resolved

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $baseName = if ($item.PSIsContainer) { $item.Name } else { [System.IO.Path]::GetFileNameWithoutExtension($item.Name) }
        $Name = "$baseName-mobile-handoff.zip"
    }

    $archivePath = Join-Path ([System.IO.Path]::GetTempPath()) $Name
    Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue

    if ($item.PSIsContainer) {
        Compress-Archive -Path (Join-Path $item.FullName "*") -DestinationPath $archivePath -Force
    }
    else {
        Compress-Archive -Path $item.FullName -DestinationPath $archivePath -Force
    }

    return (Get-Item -LiteralPath $archivePath).FullName
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$FilePath)
    return (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash
}

function Test-DownloadHash {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$ExpectedHash
    )

    $downloadPath = Join-Path ([System.IO.Path]::GetTempPath()) ("mobile-handoff-check-" + [Guid]::NewGuid().ToString("N") + ".bin")
    try {
        curl.exe -L -s -o $downloadPath $Url | Out-Null
        if (-not (Test-Path -LiteralPath $downloadPath)) {
            return @{ ok = $false; error = "download did not create a file" }
        }

        $actualHash = Get-Sha256 -FilePath $downloadPath
        if ($actualHash -ne $ExpectedHash) {
            return @{ ok = $false; error = "hash mismatch"; actualSha256 = $actualHash }
        }

        return @{ ok = $true; sha256 = $actualHash }
    }
    finally {
        Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
    }
}

function Upload-Tmpfiles {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$ExpectedHash,
        [int]$ExpireSeconds
    )

    $responseText = curl.exe -s -F "file=@$FilePath" "https://tmpfiles.org/api/v1/upload?expire=$ExpireSeconds"
    $response = $responseText | ConvertFrom-Json

    if ($response.status -ne "success" -or -not $response.data.url) {
        throw "tmpfiles upload failed: $responseText"
    }

    $pageUrl = [string]$response.data.url
    $downloadUrl = $pageUrl -replace "^https://tmpfiles\.org/", "https://tmpfiles.org/dl/"
    $check = Test-DownloadHash -Url $downloadUrl -ExpectedHash $ExpectedHash

    if (-not $check.ok) {
        throw "tmpfiles verification failed: $($check.error)"
    }

    return @{
        provider = "tmpfiles"
        url = $downloadUrl
        pageUrl = $pageUrl
        expires = "up to $ExpireSeconds seconds"
        sha256 = $check.sha256
    }
}

function Upload-Filebin {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$ExpectedHash
    )

    $fileName = [System.IO.Path]::GetFileName($FilePath)
    $responseText = curl.exe -s --data-binary "@$FilePath" -H "filename: $fileName" https://filebin.net/
    $response = $responseText | ConvertFrom-Json

    if (-not $response.bin.id -or -not $response.file.filename) {
        throw "filebin upload failed: $responseText"
    }

    $url = "https://filebin.net/$($response.bin.id)/$($response.file.filename)"
    $check = Test-DownloadHash -Url $url -ExpectedHash $ExpectedHash

    if (-not $check.ok) {
        throw "filebin verification failed: $($check.error)"
    }

    return @{
        provider = "filebin"
        url = $url
        expires = $response.bin.expired_at
        sha256 = $check.sha256
    }
}

$resolvedPath = Resolve-Path -LiteralPath $Path
$item = Get-Item -LiteralPath $resolvedPath

$uploadPath = if ($item.PSIsContainer -or $Zip.IsPresent) {
    New-TempArchive -SourcePath $item.FullName -Name $ArchiveName
}
else {
    $item.FullName
}

$localHash = Get-Sha256 -FilePath $uploadPath
$verifiedLinks = @()
$failedProviders = @()

$providersToTry = if ($Provider -eq "all") { @("tmpfiles", "filebin") } else { @($Provider) }

foreach ($providerName in $providersToTry) {
    try {
        if ($providerName -eq "tmpfiles") {
            $verifiedLinks += Upload-Tmpfiles -FilePath $uploadPath -ExpectedHash $localHash -ExpireSeconds $TmpfilesExpireSeconds
        }
        elseif ($providerName -eq "filebin") {
            $verifiedLinks += Upload-Filebin -FilePath $uploadPath -ExpectedHash $localHash
        }
    }
    catch {
        $failedProviders += @{
            provider = $providerName
            error = $_.Exception.Message
        }
    }
}

$result = [ordered]@{
    localPath = $uploadPath
    localSha256 = $localHash
    verifiedLinks = $verifiedLinks
    failedProviders = $failedProviders
}

$result | ConvertTo-Json -Depth 6

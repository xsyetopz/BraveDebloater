#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TemplateZipPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path (Join-Path $root 'config') 'policies.json'

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Read-ZipEntryText {
    param(
        [Parameter(Mandatory = $true)]$Zip,
        [Parameter(Mandatory = $true)][string]$EntryName
    )

    $entry = $Zip.GetEntry($EntryName)
    if ($null -eq $entry) {
        throw "Template zip is missing '$EntryName'."
    }

    $stream = $entry.Open()
    try {
        $reader = New-Object System.IO.StreamReader($stream, $true)
        try {
            return $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $TemplateZipPath)) {
    throw "Missing template zip: $TemplateZipPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $TemplateZipPath))
try {
    $versionText = Read-ZipEntryText -Zip $zip -EntryName 'VERSION'
    $templateVersion = (($versionText -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^(MAJOR|MINOR|BUILD|PATCH)=' }) -replace '^[^=]+='
    $templateVersion = $templateVersion -join '.'
    if ($templateVersion -ne [string]$manifest.policyTemplateVersion) {
        throw "Manifest policyTemplateVersion '$($manifest.policyTemplateVersion)' does not match template '$templateVersion'."
    }

    $admx = Read-ZipEntryText -Zip $zip -EntryName 'windows/admx/brave.admx'
    $templatePolicies = @([regex]::Matches($admx, '<policy\b[^>]*\bname="([^"]+)"') |
        ForEach-Object { $_.Groups[1].Value } |
        Where-Object { $_ -notmatch '_recommended$' } |
        Sort-Object -Unique)

    foreach ($policyName in @($manifest.policies.PSObject.Properties.Name)) {
        if ($templatePolicies -notcontains $policyName) {
            throw "Manifest policy '$policyName' is not present in the official Brave ADMX template."
        }
    }

    $iosSupported = @($manifest.platformSupport.iOS)
    foreach ($policyName in $iosSupported) {
        if ($null -eq $manifest.policies.PSObject.Properties[$policyName]) {
            throw "iOS platform support references undefined policy '$policyName'."
        }
    }
}
finally {
    $zip.Dispose()
}

Write-Host "Latest Brave template validation passed for $($manifest.policyTemplateVersion)."

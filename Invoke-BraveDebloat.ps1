#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Core', 'Privacy', 'Aggressive')]
    [string]$Preset = 'Aggressive',

    [ValidateSet('CurrentUser', 'LocalMachine')]
    [string]$Scope = 'CurrentUser',

    [switch]$Apply,

    [switch]$LockShields,

    [switch]$IncludeProfilePreferences,

    [string]$ProfileRoot = (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data'),

    [string]$BackupDirectory,

    [string]$UndoFromBackup,

    [switch]$List,

    [switch]$NoBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
    $PSScriptRoot
}

if ([string]::IsNullOrWhiteSpace($BackupDirectory)) {
    $BackupDirectory = Join-Path $ProjectRoot 'backups'
}

function Write-Step {
    param([string]$Message)
    Write-Host "[BraveDebloater] $Message"
}

function Write-DryRun {
    param([string]$Message)
    Write-Host "[dry-run] $Message"
}

function Get-Manifest {
    $manifestPath = Join-Path $ProjectRoot 'config\policies.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Cannot find policy manifest at $manifestPath."
    }

    return Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
}

function Get-ManifestMap {
    param([Parameter(Mandatory = $true)]$Object)

    $map = @{}
    foreach ($property in $Object.PSObject.Properties) {
        $map[$property.Name] = $property.Value
    }
    return $map
}

function Resolve-PresetPolicies {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][hashtable]$Presets,
        [hashtable]$Seen = @{}
    )

    if (-not $Presets.ContainsKey($Name)) {
        throw "Unknown preset '$Name'."
    }
    if ($Seen.ContainsKey($Name)) {
        throw "Preset cycle detected at '$Name'."
    }

    $Seen[$Name] = $true
    $resolved = New-Object System.Collections.Generic.List[string]

    foreach ($entry in @($Presets[$Name])) {
        if ($entry -isnot [string]) {
            throw "Preset '$Name' contains a non-string entry."
        }

        if ($entry.StartsWith('@')) {
            $childName = $entry.Substring(1)
            foreach ($childPolicy in Resolve-PresetPolicies -Name $childName -Presets $Presets -Seen ($Seen.Clone())) {
                if (-not $resolved.Contains($childPolicy)) {
                    [void]$resolved.Add($childPolicy)
                }
            }
        }
        elseif (-not $resolved.Contains($entry)) {
            [void]$resolved.Add($entry)
        }
    }

    return $resolved.ToArray()
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RegistryBasePath {
    param([string]$ScopeName)

    if ($ScopeName -eq 'LocalMachine') {
        if (-not (Test-IsAdministrator)) {
            throw 'LocalMachine scope requires an elevated PowerShell session. Use -Scope CurrentUser or run as administrator.'
        }
        return 'Registry::HKEY_LOCAL_MACHINE\Software\Policies\BraveSoftware\Brave'
    }

    return 'Registry::HKEY_CURRENT_USER\Software\Policies\BraveSoftware\Brave'
}

function Assert-PolicySafety {
    param(
        [string[]]$PolicyNames,
        [Parameter(Mandatory = $true)]$Manifest
    )

    $blockedNames = @($Manifest.safety.blockedPolicyNames)
    $blockedPatterns = @($Manifest.safety.blockedNamePatterns)

    foreach ($policyName in $PolicyNames) {
        if ($blockedNames -contains $policyName) {
            throw "Refusing to apply protected policy '$policyName'."
        }

        foreach ($pattern in $blockedPatterns) {
            if ($policyName -match $pattern) {
                throw "Refusing to apply '$policyName' because it matches protected pattern '$pattern'."
            }
        }
    }
}

function Get-RegistrySnapshot {
    param(
        [string]$BasePath,
        [string[]]$PolicyNames
    )

    $snapshot = New-Object System.Collections.Generic.List[object]
    $keyExists = Test-Path -LiteralPath $BasePath
    $key = $null
    if ($keyExists) {
        $key = Get-Item -LiteralPath $BasePath
    }

    foreach ($policyName in $PolicyNames) {
        $entry = [ordered]@{
            name = $policyName
            existed = $false
            value = $null
            kind = $null
        }

        if ($keyExists) {
            try {
                $value = $key.GetValue($policyName, $null)
                if ($null -ne $value) {
                    $entry.existed = $true
                    $entry.value = $value
                    $entry.kind = $key.GetValueKind($policyName).ToString()
                }
            }
            catch {
                $entry.existed = $false
            }
        }

        [void]$snapshot.Add([pscustomobject]$entry)
    }

    return $snapshot.ToArray()
}

function New-Backup {
    param(
        [string]$Directory,
        [string]$ScopeName,
        [string]$RegistryPath,
        [string[]]$PolicyNames,
        [Parameter(Mandatory = $true)]$Manifest
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = Join-Path $Directory "BraveDebloater-$timestamp.json"
    $backup = [ordered]@{
        schemaVersion = 1
        createdAt = (Get-Date).ToString('o')
        manifestSchemaVersion = $Manifest.schemaVersion
        policyTemplateVersion = $Manifest.policyTemplateVersion
        scope = $ScopeName
        registryPath = $RegistryPath
        policies = @(Get-RegistrySnapshot -BasePath $RegistryPath -PolicyNames $PolicyNames)
        profileFiles = @()
    }

    $backup | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Update-BackupProfileFiles {
    param(
        [string]$BackupPath,
        [object[]]$ProfileFiles
    )

    if (-not $BackupPath -or -not (Test-Path -LiteralPath $BackupPath)) {
        return
    }

    $backup = Get-Content -LiteralPath $BackupPath -Raw | ConvertFrom-Json
    $backup.profileFiles = @($ProfileFiles)
    $backup | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $BackupPath -Encoding UTF8
}

function Set-BravePolicy {
    param(
        [string]$BasePath,
        [string]$Name,
        [Parameter(Mandatory = $true)]$Definition
    )

    if (-not (Test-Path -LiteralPath $BasePath)) {
        New-Item -Path $BasePath -Force | Out-Null
    }

    $propertyType = switch ($Definition.type) {
        'DWord' { 'DWord' }
        'String' { 'String' }
        default { throw "Unsupported registry type '$($Definition.type)' for policy '$Name'." }
    }

    $value = $Definition.value
    if ($Definition.type -eq 'DWord') {
        $value = [int]$value
    }

    New-ItemProperty -LiteralPath $BasePath -Name $Name -Value $value -PropertyType $propertyType -Force | Out-Null
}

function Restore-RegistryBackup {
    param(
        [string]$BackupPath,
        [switch]$DoApply
    )

    if (-not (Test-Path -LiteralPath $BackupPath)) {
        throw "Backup file not found: $BackupPath"
    }

    $backup = Get-Content -LiteralPath $BackupPath -Raw | ConvertFrom-Json
    $registryPath = [string]$backup.registryPath

    foreach ($policy in @($backup.policies)) {
        $name = [string]$policy.name
        if (-not $DoApply) {
            if ($policy.existed) {
                Write-DryRun "Would restore $name to '$($policy.value)' ($($policy.kind))."
            }
            else {
                Write-DryRun "Would remove $name because it did not exist before."
            }
            continue
        }

        if ($policy.existed) {
            if (-not (Test-Path -LiteralPath $registryPath)) {
                New-Item -Path $registryPath -Force | Out-Null
            }

            $kind = [string]$policy.kind
            $value = $policy.value
            if ($kind -eq 'DWord') {
                $value = [int]$value
            }

            New-ItemProperty -LiteralPath $registryPath -Name $name -Value $value -PropertyType $kind -Force | Out-Null
            Write-Step "Restored $name."
        }
        elseif (Test-Path -LiteralPath $registryPath) {
            Remove-ItemProperty -LiteralPath $registryPath -Name $name -ErrorAction SilentlyContinue
            Write-Step "Removed $name."
        }
    }

    foreach ($profileFile in @($backup.profileFiles)) {
        $source = [string]$profileFile.backupPath
        $target = [string]$profileFile.originalPath

        if (-not $DoApply) {
            Write-DryRun "Would restore profile file $target."
            continue
        }

        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination $target -Force
            Write-Step "Restored profile file $target."
        }
        else {
            Write-Warning "Profile backup missing: $source"
        }
    }
}

function Get-JsonPathResult {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $current = $Object
    foreach ($part in ($Path -split '\.')) {
        if ($null -eq $current -or $null -eq $current.PSObject.Properties[$part]) {
            return [pscustomobject]@{ exists = $false; value = $null }
        }
        $current = $current.PSObject.Properties[$part].Value
    }

    return [pscustomobject]@{ exists = $true; value = $current }
}

function Set-JsonPathValue {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value,
        [bool]$CreateMissing = $false
    )

    $parts = $Path -split '\.'
    $current = $Object

    for ($i = 0; $i -lt ($parts.Count - 1); $i++) {
        $part = $parts[$i]
        if ($null -eq $current.PSObject.Properties[$part]) {
            if (-not $CreateMissing) {
                return $false
            }
            $child = [pscustomobject]@{}
            $current | Add-Member -NotePropertyName $part -NotePropertyValue $child
        }
        $current = $current.PSObject.Properties[$part].Value
    }

    $leaf = $parts[-1]
    if ($null -eq $current.PSObject.Properties[$leaf]) {
        if (-not $CreateMissing) {
            return $false
        }
        $current | Add-Member -NotePropertyName $leaf -NotePropertyValue $Value
    }
    else {
        $current.PSObject.Properties[$leaf].Value = $Value
    }

    return $true
}

function Get-BraveProfilePreferenceFiles {
    param([string]$Root)

    $files = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $Root)) {
        return $files.ToArray()
    }

    Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $preferencesPath = Join-Path $_.FullName 'Preferences'
            if (Test-Path -LiteralPath $preferencesPath) {
                [void]$files.Add($preferencesPath)
            }
        }

    return $files.ToArray()
}

function Invoke-ProfilePreferenceCleanup {
    param(
        [string]$Root,
        [Parameter(Mandatory = $true)]$Manifest,
        [string]$BackupPath,
        [switch]$DoApply
    )

    $files = @(Get-BraveProfilePreferenceFiles -Root $Root)
    if ($files.Count -eq 0) {
        Write-Warning "No Brave profile files found under $Root."
        return
    }

    if ($DoApply -and (Get-Process -Name brave -ErrorAction SilentlyContinue)) {
        Write-Warning 'Brave is running, so profile preference cleanup was skipped. Close Brave and rerun with -IncludeProfilePreferences to apply those cosmetic patches.'
        return
    }

    $profileBackups = New-Object System.Collections.Generic.List[object]
    $patches = @($Manifest.profilePreferencePatches)

    foreach ($file in $files) {
        if (-not $DoApply) {
            Write-DryRun "Would inspect profile file $file."
        }

        $json = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        $changed = $false

        foreach ($patch in $patches) {
            $path = [string]$patch.path
            if ($path -match '(?i)shield') {
                throw "Refusing profile preference patch that mentions Shields: $path"
            }

            $current = Get-JsonPathResult -Object $json -Path $path
            $createMissing = [bool]$patch.createMissing

            if (-not $current.exists -and -not $createMissing) {
                continue
            }

            if (-not $DoApply) {
                if ($current.exists) {
                    Write-DryRun "Would set $path in $file from '$($current.value)' to '$($patch.value)'."
                }
                else {
                    Write-DryRun "Would create $path in $file with '$($patch.value)'."
                }
                continue
            }

            if (Set-JsonPathValue -Object $json -Path $path -Value $patch.value -CreateMissing:$createMissing) {
                $changed = $true
            }
        }

        if ($DoApply -and $changed) {
            $profileBackupDirectory = Join-Path (Split-Path -Parent $BackupPath) 'profile-files'
            if (-not (Test-Path -LiteralPath $profileBackupDirectory)) {
                New-Item -ItemType Directory -Path $profileBackupDirectory -Force | Out-Null
            }

            $safeName = ($file -replace '[:\\\/ ]', '_')
            $profileBackupPath = Join-Path $profileBackupDirectory "$safeName.bak"
            Copy-Item -LiteralPath $file -Destination $profileBackupPath -Force
            [void]$profileBackups.Add([pscustomobject]@{
                originalPath = $file
                backupPath = $profileBackupPath
            })

            $json | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $file -Encoding UTF8
            Write-Step "Updated profile preferences in $file."
        }
    }

    if ($DoApply -and $profileBackups.Count -gt 0) {
        Update-BackupProfileFiles -BackupPath $BackupPath -ProfileFiles $profileBackups.ToArray()
    }
}

function Show-PolicyList {
    param(
        [string[]]$PolicyNames,
        [hashtable]$PolicyDefinitions
    )

    $rows = foreach ($name in $PolicyNames) {
        $definition = $PolicyDefinitions[$name]
        [pscustomobject]@{
            Policy = $name
            Value = $definition.value
            Category = $definition.category
            Reason = $definition.reason
        }
    }

    $rows | Format-Table -AutoSize
}

$manifest = Get-Manifest

if ($UndoFromBackup) {
    Restore-RegistryBackup -BackupPath $UndoFromBackup -DoApply:$Apply
    if (-not $Apply) {
        Write-Step 'Undo dry-run complete. Rerun with -Apply to restore the backup.'
    }
    else {
        Write-Step 'Undo complete. Restart Brave, then open brave://policy to verify.'
    }
    return
}

$presets = Get-ManifestMap -Object $manifest.presets
$policyDefinitions = Get-ManifestMap -Object $manifest.policies
$policyNames = New-Object System.Collections.Generic.List[string]

foreach ($name in Resolve-PresetPolicies -Name $Preset -Presets $presets) {
    [void]$policyNames.Add($name)
}

if ($LockShields) {
    foreach ($name in Resolve-PresetPolicies -Name 'ShieldBaseline' -Presets $presets) {
        if (-not $policyNames.Contains($name)) {
            [void]$policyNames.Add($name)
        }
    }
}

foreach ($policyName in $policyNames) {
    if (-not $policyDefinitions.ContainsKey($policyName)) {
        throw "Policy '$policyName' is referenced by a preset but not defined."
    }
}

Assert-PolicySafety -PolicyNames $policyNames.ToArray() -Manifest $manifest

if ($List) {
    Show-PolicyList -PolicyNames $policyNames.ToArray() -PolicyDefinitions $policyDefinitions
    if (-not $IncludeProfilePreferences) {
        return
    }
}

$registryPath = Get-RegistryBasePath -ScopeName $Scope

Write-Step "Preset: $Preset"
Write-Step "Scope: $Scope ($registryPath)"
if ($LockShields) {
    Write-Step 'Shield baseline: enabled. This enforces ad blocking, standard fingerprinting protection, HTTPS upgrade, and referrer capping.'
}
else {
    Write-Step 'Shield baseline: not locked. This tool will not disable or whitelist Brave Shields.'
}

if (-not $Apply) {
    Write-Step 'Dry-run mode. No registry or profile files will be changed.'
}

if ($IncludeProfilePreferences -and $Apply -and $NoBackup) {
    throw 'Profile preference cleanup requires backups. Remove -NoBackup or omit -IncludeProfilePreferences.'
}

$backupPath = $null
if ($Apply -and -not $NoBackup) {
    $backupPath = New-Backup -Directory $BackupDirectory -ScopeName $Scope -RegistryPath $registryPath -PolicyNames $policyNames.ToArray() -Manifest $manifest
    Write-Step "Backup written to $backupPath"
}

foreach ($policyName in $policyNames) {
    $definition = $policyDefinitions[$policyName]
    if (-not $Apply) {
        Write-DryRun "Would set $policyName = $($definition.value) ($($definition.reason))"
        continue
    }

    if ($PSCmdlet.ShouldProcess($registryPath, "Set $policyName to $($definition.value)")) {
        Set-BravePolicy -BasePath $registryPath -Name $policyName -Definition $definition
        Write-Step "Set $policyName."
    }
}

if ($IncludeProfilePreferences) {
    Invoke-ProfilePreferenceCleanup -Root $ProfileRoot -Manifest $manifest -BackupPath $backupPath -DoApply:$Apply
}

if (-not $Apply) {
    Write-Step 'Dry-run complete. Rerun with -Apply to make changes.'
}
else {
    Write-Step 'Done. Restart Brave, then open brave://policy to verify the applied policies.'
}

#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'Invoke-BraveDebloat.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('BraveDebloaterBehavior-{0}' -f [guid]::NewGuid().ToString('N'))

function Assert-TextContains {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if (-not $Text.Contains($Expected)) {
        throw "$Context did not contain expected text: $Expected"
    }
}

function Assert-TextDoesNotContain {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Unexpected,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ($Text.Contains($Unexpected)) {
        throw "$Context contained unexpected text: $Unexpected"
    }
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    $missingProfileRoot = Join-Path $tempRoot 'MissingProfileRoot'
    $listOutput = (& $scriptPath -Preset Core -List -IncludeProfilePreferences -ProfileRoot $missingProfileRoot *>&1 | Out-String)
    Assert-TextContains -Text $listOutput -Expected 'Profile preference patches' -Context '-List output'
    Assert-TextContains -Text $listOutput -Expected 'brave.new_tab_page.show_branded_background_image' -Context '-List output'
    Assert-TextDoesNotContain -Text $listOutput -Unexpected '[dry-run]' -Context '-List output'

    $featureOutput = (& $scriptPath -Preset Extreme -ListFeatures *>&1 | Out-String)
    Assert-TextContains -Text $featureOutput -Expected 'LeoAI' -Context '-ListFeatures output'
    Assert-TextContains -Text $featureOutput -Expected 'Brave Rewards' -Context '-ListFeatures output'

    $doctorBackupDirectory = Join-Path $tempRoot 'DoctorBackups'
    New-Item -ItemType Directory -Path $doctorBackupDirectory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $doctorBackupDirectory 'BraveDebloater-20260101-010101-001.json') -Value '{}' -Encoding UTF8

    $doctorOutput = (& $scriptPath -Doctor -ProfileRoot $missingProfileRoot -BackupDirectory $doctorBackupDirectory *>&1 | Out-String)
    Assert-TextContains -Text $doctorOutput -Expected 'Doctor report (read-only)' -Context '-Doctor output'
    Assert-TextContains -Text $doctorOutput -Expected 'CurrentUser policies' -Context '-Doctor output'
    Assert-TextContains -Text $doctorOutput -Expected 'LocalMachine policies' -Context '-Doctor output'
    Assert-TextContains -Text $doctorOutput -Expected 'Feature status' -Context '-Doctor output'
    Assert-TextContains -Text $doctorOutput -Expected 'Backups: 1 found' -Context '-Doctor output'
    Assert-TextContains -Text $doctorOutput -Expected 'Profile root: missing' -Context '-Doctor output'
    Assert-TextDoesNotContain -Text $doctorOutput -Unexpected '[dry-run]' -Context '-Doctor output'
    Assert-TextDoesNotContain -Text $doctorOutput -Unexpected 'Would set' -Context '-Doctor output'

    $doctorApplyBackupDirectory = Join-Path $tempRoot 'DoctorApplyBackups'
    $doctorApplyOutput = (& $scriptPath -Doctor -Apply -ProfileRoot $missingProfileRoot -BackupDirectory $doctorApplyBackupDirectory *>&1 | Out-String)
    Assert-TextContains -Text $doctorApplyOutput -Expected '-Doctor is read-only. -Apply is ignored in Doctor mode.' -Context '-Doctor -Apply output'
    Assert-TextContains -Text $doctorApplyOutput -Expected 'Doctor report (read-only)' -Context '-Doctor -Apply output'
    Assert-TextDoesNotContain -Text $doctorApplyOutput -Unexpected 'Backup written' -Context '-Doctor -Apply output'
    Assert-TextDoesNotContain -Text $doctorApplyOutput -Unexpected 'Would set' -Context '-Doctor -Apply output'
    if (Test-Path -LiteralPath $doctorApplyBackupDirectory) {
        throw '-Doctor -Apply created a backup directory.'
    }

    $excludeOutput = (& $scriptPath -Preset Extreme -ExcludeFeature News,LeoAI -List *>&1 | Out-String)
    Assert-TextContains -Text $excludeOutput -Expected 'BraveRewardsDisabled' -Context '-ExcludeFeature output'
    Assert-TextDoesNotContain -Text $excludeOutput -Unexpected 'BraveNewsDisabled' -Context '-ExcludeFeature output'
    Assert-TextDoesNotContain -Text $excludeOutput -Unexpected 'BraveAIChatEnabled' -Context '-ExcludeFeature output'

    $includeOutput = (& $scriptPath -Preset Standard -IncludeFeature Translate -List *>&1 | Out-String)
    Assert-TextContains -Text $includeOutput -Expected 'TranslateEnabled' -Context '-IncludeFeature output'

    $onlyOutput = (& $scriptPath -OnlyFeature Rewards,Wallet -List *>&1 | Out-String)
    Assert-TextContains -Text $onlyOutput -Expected 'BraveRewardsDisabled' -Context '-OnlyFeature output'
    Assert-TextContains -Text $onlyOutput -Expected 'BraveWalletDisabled' -Context '-OnlyFeature output'
    Assert-TextDoesNotContain -Text $onlyOutput -Unexpected 'BraveVPNDisabled' -Context '-OnlyFeature output'
    Assert-TextDoesNotContain -Text $onlyOutput -Unexpected 'BraveAIChatEnabled' -Context '-OnlyFeature output'

    $onlyPatchOutput = (& $scriptPath -OnlyFeature Rewards -List -IncludeProfilePreferences *>&1 | Out-String)
    Assert-TextContains -Text $onlyPatchOutput -Expected 'brave.rewards.enabled' -Context '-OnlyFeature profile patch output'
    Assert-TextDoesNotContain -Text $onlyPatchOutput -Unexpected 'brave.new_tab_page.show_branded_background_image' -Context '-OnlyFeature profile patch output'
    Assert-TextDoesNotContain -Text $onlyPatchOutput -Unexpected 'brave.wallet.show_wallet_icon_on_toolbar' -Context '-OnlyFeature profile patch output'

    $onlyDryRunOutput = (& $scriptPath -OnlyFeature Rewards *>&1 | Out-String)
    Assert-TextContains -Text $onlyDryRunOutput -Expected 'Preset: (none - OnlyFeature mode)' -Context '-OnlyFeature dry-run output'
    Assert-TextContains -Text $onlyDryRunOutput -Expected 'Custom features: Rewards' -Context '-OnlyFeature dry-run output'
    Assert-TextDoesNotContain -Text $onlyDryRunOutput -Unexpected 'Preset: Extreme' -Context '-OnlyFeature dry-run output'

    $blankOnlyFeatureFailed = $false
    try {
        & $scriptPath -OnlyFeature ' ' | Out-Null
    }
    catch {
        $blankOnlyFeatureFailed = $_.Exception.Message -match 'Specified -OnlyFeature contains only blank entries'
    }
    if (-not $blankOnlyFeatureFailed) {
        throw '-OnlyFeature did not reject blank-only input.'
    }

    $onlyConflictCommands = @(
        { & $scriptPath -OnlyFeature Rewards -ExcludeFeature Wallet -List | Out-Null },
        { & $scriptPath -OnlyFeature Rewards -IncludeFeature Wallet -List | Out-Null },
        { & $scriptPath -OnlyFeature Rewards -Customize -List | Out-Null }
    )
    foreach ($command in $onlyConflictCommands) {
        $onlyConflictFailed = $false
        try {
            & $command
        }
        catch {
            $onlyConflictFailed = $_.Exception.Message -match 'OnlyFeature cannot be combined'
        }
        if (-not $onlyConflictFailed) {
            throw '-OnlyFeature did not reject a conflicting custom feature switch.'
        }
    }

    $filteredPatchOutput = (& $scriptPath -Preset Extreme -ExcludeFeature News,Rewards,Wallet -List -IncludeProfilePreferences *>&1 | Out-String)
    Assert-TextContains -Text $filteredPatchOutput -Expected 'brave.new_tab_page.show_branded_background_image' -Context 'filtered profile patch output'
    Assert-TextDoesNotContain -Text $filteredPatchOutput -Unexpected 'brave.today.should_show_toolbar_button' -Context 'filtered profile patch output'
    Assert-TextDoesNotContain -Text $filteredPatchOutput -Unexpected 'brave.rewards.enabled' -Context 'filtered profile patch output'
    Assert-TextDoesNotContain -Text $filteredPatchOutput -Unexpected 'brave.wallet.show_wallet_icon_on_toolbar' -Context 'filtered profile patch output'

    $whatIfBackupDirectory = Join-Path $tempRoot 'WhatIfBackups'
    $whatIfOutput = (& $scriptPath -Preset Core -Apply -WhatIf -BackupDirectory $whatIfBackupDirectory *>&1 | Out-String)
    Assert-TextContains -Text $whatIfOutput -Expected 'WhatIf mode. No registry, backup, or profile files will be changed.' -Context '-WhatIf output'
    Assert-TextDoesNotContain -Text $whatIfOutput -Unexpected 'Backup written' -Context '-WhatIf output'
    Assert-TextDoesNotContain -Text $whatIfOutput -Unexpected 'Done. Restart Brave' -Context '-WhatIf output'
    if (Test-Path -LiteralPath $whatIfBackupDirectory) {
        throw '-WhatIf created a backup directory.'
    }

    $tamperedBackup = Join-Path $tempRoot 'tampered-backup.json'
    [ordered]@{
        schemaVersion = 1
        registryPath = 'Registry::HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows'
        policies = @()
        profileFiles = @()
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tamperedBackup -Encoding UTF8

    $failedAsExpected = $false
    try {
        & $scriptPath -UndoFromBackup $tamperedBackup | Out-Null
    }
    catch {
        $failedAsExpected = $_.Exception.Message -match 'untrusted registry path'
    }
    if (-not $failedAsExpected) {
        throw 'Tampered backup did not fail with the expected restore validation error.'
    }

    $validBackup = Join-Path $tempRoot 'valid-backup.json'
    [ordered]@{
        schemaVersion = 1
        registryPath = 'Registry::HKEY_CURRENT_USER\Software\Policies\BraveSoftware\Brave'
        policies = @(
            [ordered]@{
                name = 'BraveRewardsDisabled'
                existed = $false
                value = $null
                kind = $null
            }
        )
        profileFiles = @()
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $validBackup -Encoding UTF8

    $restoreOutput = (& $scriptPath -UndoFromBackup $validBackup *>&1 | Out-String)
    Assert-TextContains -Text $restoreOutput -Expected 'Would remove BraveRewardsDisabled' -Context 'restore dry-run output'

    Write-Host 'Behavior checks passed.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

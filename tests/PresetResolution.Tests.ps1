#requires -Version 5.1

Describe 'Preset resolution' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        . (Join-Path $root 'src/Common.ps1')
        . (Join-Path $root 'src/Manifest.ps1')

        $manifest = Get-Content -LiteralPath (Join-Path (Join-Path $root 'config') 'policies.json') -Raw | ConvertFrom-Json
        $presets = Get-ManifestMap -Object $manifest.presets
    }

    It 'resolves preset aliases to the same policies' {
        (Resolve-PresetPolicies -Name 'Standard' -Presets $presets) -join ',' | Should -Be ((Resolve-PresetPolicies -Name 'Core' -Presets $presets) -join ',')
        (Resolve-PresetPolicies -Name 'High' -Presets $presets) -join ',' | Should -Be ((Resolve-PresetPolicies -Name 'Privacy' -Presets $presets) -join ',')
        (Resolve-PresetPolicies -Name 'Extreme' -Presets $presets) -join ',' | Should -Be ((Resolve-PresetPolicies -Name 'Aggressive' -Presets $presets) -join ',')
    }

    It 'rejects unknown presets clearly' {
        { Resolve-PresetPolicies -Name 'Missing' -Presets $presets } | Should -Throw "Unknown preset 'Missing'."
    }

    It 'rejects preset cycles' {
        $cycle = @{
            A = @('@B')
            B = @('@A')
        }

        { Resolve-PresetPolicies -Name 'A' -Presets $cycle } | Should -Throw "Preset cycle detected at 'A'."
    }
}

Describe 'Backup retention' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        . (Join-Path $root 'src/Common.ps1')
        . (Join-Path $root 'src/Backup.ps1')
    }

    It 'keeps deleting backups after one removal fails' {
        $directory = Join-Path ([System.IO.Path]::GetTempPath()) ('BraveDebloaterPester-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        try {
            foreach ($name in @('BraveDebloater-pass1.json', 'BraveDebloater-fail.json', 'BraveDebloater-pass2.json')) {
                Set-Content -LiteralPath (Join-Path $directory $name) -Value '{}' -Encoding UTF8
            }

            Mock Remove-Item {
                if ($LiteralPath -like '*fail.json') {
                    throw 'locked'
                }
            }
            Mock Write-Warning {}

            Invoke-BackupRetention -Directory $directory -KeepLatest 0 -DoApply

            Should -Invoke Remove-Item -Times 3 -Exactly
            Should -Invoke Write-Warning -Times 1 -Exactly
        }
        finally {
            Microsoft.PowerShell.Management\Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

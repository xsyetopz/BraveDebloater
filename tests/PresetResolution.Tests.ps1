#requires -Version 5.1

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/Common.ps1')
. (Join-Path $root 'src/Manifest.ps1')

Describe 'Preset resolution' {
    BeforeAll {
        $manifest = Get-Manifest
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

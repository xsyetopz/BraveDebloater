# Changelog

## Unreleased

- Skip unreadable or invalid profile `Preferences` files with a warning instead of failing the whole profile preference cleanup run.
- Added `-Doctor` for a read-only Brave policy, feature, backup, profile, and safety diagnostic report.
- Added Greptile review configuration for safety-focused pull request feedback.
- Added `-OnlyFeature` for running exactly selected feature cleanups without starting from a preset.

## 0.2.0 - 2026-05-04

- Added friendly `Standard`, `High`, and `Extreme` presets while keeping the original preset names as aliases.
- Added `-Customize`, `-IncludeFeature`, `-ExcludeFeature`, and `-ListFeatures` for feature-level cleanup choices.
- Filter profile preference cleanup by selected features when custom choices are used.

## 0.1.1 - 2026-05-03

- Made `-List` a read-only listing path, including optional profile preference patch listing.
- Added safer `-WhatIf` handling, restore backup validation, collision-resistant backup names, and atomic JSON file writes.
- Added behavior checks and Windows PowerShell 5.1 CI coverage.

## 0.1.0

- Initial safety-first Brave debloater.
- Added Core, Privacy, Aggressive, and optional Shield baseline policy sets.
- Added dry-run default, backup creation, restore flow, profile preference cleanup, and manifest checks.

# Changelog

## Unreleased

- Made `-List` a read-only listing path, including optional profile preference patch listing.
- Added safer `-WhatIf` handling, restore backup validation, collision-resistant backup names, and atomic JSON file writes.
- Added behavior checks and Windows PowerShell 5.1 CI coverage.

## 0.1.0

- Initial safety-first Brave debloater.
- Added Core, Privacy, Aggressive, and optional Shield baseline policy sets.
- Added dry-run default, backup creation, restore flow, profile preference cleanup, and manifest checks.

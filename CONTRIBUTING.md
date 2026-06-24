# Contributing

[![Contributions welcome](https://img.shields.io/badge/contributions-welcome-2ea44f?style=flat-square&logo=github&logoColor=white)](https://github.com/osfv/BraveDebloater/issues)

Thanks for helping make BraveDebloater safer and cleaner.

## Rules For Policy Changes

- Prefer official Brave or Chromium enterprise policies over profile JSON edits.
- Do not add policies that disable Brave Shields, whitelist URLs from Shields, weaken Safe Browsing, or disable browser/component updates.
- Add every policy to `config/policies.json` with a clear category and reason.
- Add or update a friendly feature toggle when a policy should be user-selectable.
- Keep dry-run output understandable for non-experts.
- Keep restore behavior working whenever a new write path is added.
- Treat `-List` and `-WhatIf` as read-only paths.

## AI Agent And LLM Contributions

If an AI agent, coding assistant, or autonomous workflow changes this repository, it must follow `AGENTS.md`.

Agent-made changes must stay coherent across code, docs, tests, and configuration. If a change touches policy behavior, platform behavior, restore behavior, user-facing output, or CI, update every affected file in the same pull request.

Do not submit agent output that only patches the visible symptom. Trace the shared path, fix the common cause, and run the checks below.

## Checks

Before opening a pull request, run:

```powershell
.\scripts\Test-PolicyManifest.ps1
.\scripts\Test-Behavior.ps1
.\Invoke-BraveDebloat.ps1 -Preset Extreme -LockShields
```

The second command should stay a dry-run unless you pass `-Apply`.

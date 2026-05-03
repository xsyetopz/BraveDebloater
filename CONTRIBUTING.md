# 🤝 Contributing

Thanks for helping make BraveDebloater safer and cleaner.

## Rules For Policy Changes

- Prefer official Brave or Chromium enterprise policies over profile JSON edits.
- Do not add policies that disable Brave Shields, whitelist URLs from Shields, weaken Safe Browsing, or disable browser/component updates.
- Add every policy to `config/policies.json` with a clear category and reason.
- Keep dry-run output understandable for non-experts.
- Keep restore behavior working whenever a new write path is added.

## ✅ Checks

Before opening a pull request, run:

```powershell
.\scripts\Test-PolicyManifest.ps1
.\Invoke-BraveDebloat.ps1 -Preset Aggressive -LockShields
```

The second command should stay a dry-run unless you pass `-Apply`.

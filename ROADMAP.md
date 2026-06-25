# Roadmap

BraveDebloater stays safety-first: dry-run by default, native policy writes, strict restore validation, and no policies that weaken Brave Shields, Safe Browsing, updates, or installed extensions.

## Safety

- Keep backup and restore validation narrow.
- Keep profile preference cleanup opt-in and skipped while Brave is running.
- Add policy changes only when they are documented by Brave or Chromium policy sources.

## Testing

- Keep manifest, behavior, Pester, and PowerShell syntax checks in CI.
- Expand tests when new CLI switches change write behavior.
- Validate policy names against Brave's latest templates before releases.

## Release Trust

- Publish SHA256 checksum files beside release archives.
- Keep release notes short and focused on user-visible changes.
- Document how to verify downloads before applying changes.

## User Experience

- Improve examples for Brave Stable, Beta, and Nightly profiles.
- Keep output concise: what would change, what changed, and what to do next.
- Accept user-provided screenshots for common dry-run and Doctor workflows.

## Maintainability

- Keep `Invoke-BraveDebloat.ps1` as a thin entrypoint.
- Put shared behavior in `src/*.ps1`.
- Prefer small issue-sized changes over broad rewrites.

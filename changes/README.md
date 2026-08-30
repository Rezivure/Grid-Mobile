# Release Notes

Each PR that affects users should add a file: `changes/pr-<number>.md`

## Format

One line per change, prefixed with a tag:

```
[feature] Added group chat support
[fix] Map no longer crashes with offline tiles
[improvement] Faster message sync
```

### Tags
- `[feature]` — New functionality
- `[fix]` — Bug fix
- `[improvement]` — Enhancement to existing feature
- `[internal]` — Won't be shown in store release notes (CI, refactors, etc)

### Rules
- **One line per change.** No paragraphs.
- **Write for users**, not developers. "Fixed crash on map" not "nil check on TileProvider"
- **Skip internal-only PRs** or tag them `[internal]`
- Files are cleared after each release — but notes do **not** depend on that.
  `scripts/build-release-notes.sh` only reads files added since the previous
  release tag, so a release's notes describe that release alone even if the
  cleanup commit never lands (it is pushed to a protected branch and can be
  rejected). If you see stale `pr-*.md` files sitting here, they are harmless;
  they just were not swept up.

# Playlist
*A space for focus, one task at a time.*
https://playlist.day/

## Download links

Publishing a release here fires `.github/workflows/update-short-links.yml`,
which re-points the Short.io download links at that release's assets:

| Slug on `link.brandonkboswell.com` | Asset |
| --- | --- |
| `playlist-mac.dmg` | `*-arm64.dmg` |
| `playlist-mac-apple-silicon.dmg` | `*-arm64.dmg` |
| `playlist-mac-intel.dmg` | `*-x64.dmg` |

Attach the installers to the draft **before** hitting Publish — the workflow
only sees assets that are already on the release. If you publish first, re-run
it from the Actions tab with the tag and `dry_run: false`.

Requires a `SHORTIO_API_KEY` repository secret (Short.io → Integrations & API).
Pre-releases are skipped.

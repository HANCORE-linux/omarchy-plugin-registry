# Client contract — `omarchy plugin` ⇄ plugins.omarchy.org

The registry-side contract for the Quattro CLI work. The client stays a thin
fetch-verify-unpack; everything clever is server-side. Git installs remain the
dev escape hatch behind `--unsafe`.

## Trust root

Pin the registry public key (fetch once from `GET /signing-key.pub`, ship a
copy with Omarchy). Every JSON file below has a detached Ed25519 signature as a
real sibling object at `<path>.sig` (base64 over the exact file bytes) — works
identically from Rails or a dumb object store/CDN. Verify before trusting; the
kill list especially.

## Endpoints (all static, CDN-cached)

| Path | Contents |
|---|---|
| `GET /config.json` | URL templates: `dl`, `index`, `revocations`, `signing_key`, `api` |
| `GET /index/<publisher>/<name>.json` | One JSON line per version: `id`, `vers`, `sha256`, `size`, `yanked`, `license`, `minOmarchyVersion`, `kinds`, `caps` |
| `GET /all.json` | Compact directory listing (search/`plugin available`) |
| `GET /revocations.json` | `{schemaVersion, revocations: [{plugin, version?, reason, revoked_at}]}` — `version` absent = whole plugin |
| `GET /dl/<publisher>/<name>/<name>-<version>.tar.gz` | Immutable tarball |

## `omarchy plugin add <publisher>/<name>`

1. Fetch + verify the plugin's index file; pick the highest non-`yanked`
   version whose `minOmarchyVersion` is satisfied.
2. Fetch + verify `revocations.json`; abort if the selection is revoked.
3. Download the tarball; check SHA-256 against the index entry.
4. Existing flow unchanged: `omarchy-plugin-validate` on the staged unpack,
   id-collision check, move to `~/.config/omarchy/plugins/<id>/`, land
   **disabled** (enable stays a separate consent step).
5. Write an install receipt next to the manifest:
   `{"source": "registry", "publisher": ..., "name": ..., "version": ..., "sha256": ...}`.
   No receipt = local dev plugin: never updated, never revoked.
6. Show the capability summary (`caps`) in the confirmation prompt.

## `omarchy plugin update`

Receipted registry installs resolve by version (semver, non-yanked, compatible);
git installs keep today's fetch-diff-ff flow. Every update re-checks
`revocations.json`.

## Kill-bit check

On `add`, on `update`, and periodically (systemd user timer or shell start):
fetch + verify `revocations.json` (it is a tiny, cacheable, unparameterized GET,
empty almost always — document it as the one background network touch, with a
config switch to disable). On a hit for an installed plugin@version:

1. Disable the plugin immediately via the existing IPC.
2. Rename `~/.config/omarchy/plugins/<id>` to `<id>.quarantined-<date>`.
3. `omarchy-notification-send` with the reason and a link to the plugin page.

## Publishing (CLI side)

- `omarchy plugin publish`: device flow — `POST /api/v1/device/code` →
  `{device_code, user_code, verification_uri, interval}`; open/show
  `verification_uri`, poll `POST /api/v1/device/token {device_code}` until
  `{token}`; then `POST /api/v1/plugins/<publisher>/<name>/versions` with
  `Authorization: Bearer <token>` and the tar.gz as the raw body. 201 means
  accepted into the review pipeline (live after a short hold), 409 means the
  version number is burned, 422 carries a human-readable validation error.
- CI: exchange a GitHub Actions OIDC token (`aud: plugins.omarchy.org`) at
  `POST /api/v1/trusted/exchange {token}` for a 30-minute publish token. The
  job must run from a tag ref (`refs/tags/*`) inside the registered pinned
  environment; the repo's numeric identity is pinned on first exchange.
- `omarchy plugin new` should scaffold `manifest.json` (with `license`,
  `repository`), a widget, a readme, and the trusted-publishing workflow.

## Demotions at launch

`omarchy plugin add <git-url>` requires `--unsafe` and keeps the scary warning.
The manual stops documenting git URLs as a distribution mechanism.

# Deploying plugins.omarchy.org

One Rails app (control plane) + a directory of static files (data plane) synced
to object storage behind a CDN. Installs never touch Rails.

## Required environment

| Variable | Purpose |
|---|---|
| `SECRET_KEY_BASE` | Rails secrets (also derives the device-flow token encryptor) |
| `REGISTRY_SIGNING_SEED` | Base64 32-byte Ed25519 seed — signs every index file and the kill list. Generate: `ruby -red25519 -rbase64 -e 'puts Base64.strict_encode64(Ed25519::SigningKey.generate.seed)'`. **Custody per the governance page; losing it means re-pinning every client.** |
| `REGISTRY_BASE_URL` | `https://plugins.omarchy.org` |
| `REGISTRY_PREVIOUS_SIGNING_PUBKEY` | Rotation only: the OLD base64 public key. **Rotation is a coordinated incompatible event** — deployed clients pin one key and fail closed until they re-pin. A key swap requires `REGISTRY_ALLOW_KEY_ROTATION=1`, this variable matching the on-disk trust root (so every surviving signed file keeps verifying fail-closed), **and** `REGISTRY_ROTATION_ACK=clients-must-repin` acknowledging the client impact. Remove all three after the first post-rotation regeneration. |
| `REGISTRY_WITNESS_PATH` | Strongly recommended: a file on storage SEPARATE from the app volume (second disk, object-store mount). Each regeneration records the signed kill-list generation there; after a full-volume restore the witness proves the data plane is older than the last published kill list and regeneration refuses to sign a newer empty one until `registry:import_revocations` restores the authoritative copy (`REGISTRY_RESTORE_ACK=1` overrides once, deliberately). Unset = a full-volume restore to a pre-revocation state is locally undetectable. |
| `REGISTRY_HOST` | Host-authorization allowlist (defaults to `plugins.omarchy.org`). Requests carrying any other `Host` are rejected — session cookies are never minted for attacker-pointed domains. `ADDITIONAL_HOSTS` (comma-separated) adds extras; `/up` is exempt for by-IP health checks. |
| `SMTP_ADDRESS` / `SMTP_PORT` / `SMTP_USERNAME` / `SMTP_PASSWORD` | Login-code email delivery |
| `AI_REVIEW_COMMAND` | Optional — enables LLM review in the pipeline (escalate-only). The command runs with a scrubbed environment (no app secrets); it should call a REMOTE model API with its own credentials, and for full isolation run it under a separate UID (systemd DynamicUser or a sidecar). Note the adapter receives UNPUBLISHED submissions and previous source — treat its endpoint as a confidential-data processor. |

## Pieces

1. **Web**: `bin/thrust bin/rails server` (Dockerfile is ready). SQLite lives
   under `/rails/storage` — you MUST mount a persistent volume there
   (`docker run -v registry-storage:/rails/storage …`), or replacing the
   container loses accounts, ownership, audit, and revocation state. The same
   mount also persists the data plane. To move to Postgres instead, add
   `gem "pg"` and point `production.primary` at `DATABASE_URL`.
2. **Jobs**: `bin/jobs` (Solid Queue) — runs the review pipeline, hold-window
   releases, and index regeneration. Required.
3. **Data plane**: `storage/data_plane/` is the CDN origin. Either serve the
   Rails routes (`/index`, `/dl`, `/revocations.json`, `*.sig`, …) behind the
   CDN, or sync the directory to object storage and point the CDN there.
   Sync index files with `--delete`; sync `/dl/` WITHOUT `--delete` (tarballs
   are immutable, and `registry:regenerate` re-freezes any missing ones from
   Active Storage — note those blobs live on the SAME `/rails/storage` volume
   by default, so back that volume up as one unit, or point Active Storage at
   object storage so uploads survive volume loss independently). Keep TTLs
   short (~60 s) on index files and long on `/dl/`.
   The kill list is additionally self-healing: regeneration merges the signed
   on-disk `revocations.json` back into the database, so a database restored
   from a pre-revocation backup cannot silently revive revoked malware.
4. **Domains**: `plugins.omarchy.org` → app/CDN; `omarchyplugins.com` → 301.

## First boot

```sh
bin/rails db:prepare
bin/rails registry:grant_admin[you@omarchy.org]   # admin bootstrap — required before any takedown control works
```

The new admin signs in (email code), enrolls a passkey or TOTP, and `/admin`
unlocks. Every containment control requires an admin with a verified second
factor.

## Seeding day

```sh
bin/rails registry:seed_catalog[catalog.json]   # catalog from omarchyplugins.com listing
bin/rails registry:process_reviews              # or let bin/jobs drain the queue
```

Then notify listed authors to claim: each publisher page shows the
repo-proof claim flow. Seeded plugins that failed the pipeline stay visible as
under-review and uninstallable.

## Day-2 controls

- Admin queue: `/admin` (quarantined/held versions, reports, kill list).
- `bin/rails registry:regenerate` rebuilds the whole data plane from the DB.
- Publish hold window: `config.x.publish_hold` (15 min default in production).

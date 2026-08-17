# Deploying plugins.omarchy.org

One Rails app (control plane) + a directory of static files (data plane) synced
to object storage behind a CDN. Installs never touch Rails.

## Required environment

| Variable | Purpose |
|---|---|
| `SECRET_KEY_BASE` | Rails secrets (also derives the device-flow token encryptor) |
| `REGISTRY_SIGNING_SEED` | Base64 32-byte Ed25519 seed — signs every index file and the kill list. Generate: `ruby -red25519 -rbase64 -e 'puts Base64.strict_encode64(Ed25519::SigningKey.generate.seed)'`. **Custody per the governance page; losing it means re-pinning every client.** |
| `REGISTRY_BASE_URL` | `https://plugins.omarchy.org` |
| `SMTP_ADDRESS` / `SMTP_PORT` / `SMTP_USERNAME` / `SMTP_PASSWORD` | Login-code email delivery |
| `AI_REVIEW_COMMAND` | Optional — enables LLM review in the pipeline (escalate-only) |

## Pieces

1. **Web**: `bin/thrust bin/rails server` (Dockerfile is ready). SQLite on a
   persistent volume by default; to move to Postgres, add `gem "pg"`, point
   `production.primary` at `DATABASE_URL`, and keep the solid_* databases on
   SQLite or move them too.
2. **Jobs**: `bin/jobs` (Solid Queue) — runs the review pipeline, hold-window
   releases, and index regeneration. Required.
3. **Data plane**: `storage/data_plane/` is the CDN origin. Either serve the
   Rails routes (`/index`, `/dl`, `/revocations.json`, …) behind the CDN, or
   sync the directory to object storage (`aws s3 sync --delete` on a
   post-regeneration hook) and point the CDN there. Keep TTLs short (~60 s) on
   index files and long on `/dl/` (immutable).
4. **Domains**: `plugins.omarchy.org` → app/CDN; `omarchyplugins.com` → 301.

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

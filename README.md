# Omarchy Plugin Registry

The hosted plugin registry for [Omarchy](https://omarchy.org) Quattro —
`plugins.omarchy.org`. A Rails control plane serving a crates.io-style static
data plane: append-only JSON index + immutable, checksummed tarballs, with
registry-native accounts, automated review, and a kill-bit for revoking
already-installed plugins.

Full design: [docs/design.md](docs/design.md). Branding: [docs/branding.md](docs/branding.md)
(matches Omacom / [omacon.org](https://www.omacon.org)).

## Architecture in one paragraph

The Rails app handles accounts (mandatory publisher MFA), namespaces
(`publisher/name`, first-claim), publishing (short-lived scoped tokens; OIDC
trusted publishing later), review, and admin (quarantine / yank / kill-bit).
On every accepted publish it regenerates static index files and freezes the
tarball — installs never touch Rails in the hot path. Clients
(`omarchy plugin add publisher/name`) fetch index + tarball from the CDN,
verify checksums, and check a tiny signed `revocations.json` kill list.

## Development

```sh
bin/setup          # install gems, prepare DB
bin/dev            # run the app at localhost:3000
bin/rails test     # run tests
```

Ruby 3.4.7 (`.ruby-version`, mise-managed), Rails 8.1, SQLite in development
(Postgres at deploy), Solid Queue/Cache/Cable, Propshaft + importmap — no Node
build step.

## Status

Phase 1 (registry MVP) in progress — see `docs/design.md` §11 for the phased
rollout plan.

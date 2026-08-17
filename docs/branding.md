# Branding

Canonical brand source: **[docs/DESIGN.md](DESIGN.md)** — the Omacom design system,
fetched from the Mosaic `omacom` namespace theme (`mosaic design omacom`). Refresh it
from Mosaic when the theme updates; don't hand-edit it here.

Quick orientation (details and rules live in DESIGN.md):

- Paper `#F8F5F2` + ink `#0D0826`, the only neutral world; dark mode swaps them.
- Accent: magenta `#ED4CC8` on paper, pink `#FF8AFF` on ink (never pink text on paper).
- Type: Clash Grotesk (400–600) for headings only; JetBrains Mono for everything else.
- Structure: 1px ink hairlines + 1px offset rule-shadows; square cards; only buttons/pills round.
- Signatures: magenta `◆` bullets, dotted term underlines, uppercase mono eyebrows,
  pink flood on hover/active, noise texture on dark, neon glow once per page.
- Semantic extensions for registry security states: success `#2EA879`, warning `#E8A33D`,
  danger `#E04848` (true red, deliberately not confusable with brand pink), info `#6E7BE8`.
- Brand mark: circle · square · diamond with knockouts (SVG in DESIGN.md); glows on ink,
  flat on paper.

Reference implementation of the brand: https://github.com/omacom-io/omacon-site

# Branding — match Omacom / omacon.org

Source of truth: https://www.omacon.org/ (assets/css/root.css captured 2026-08-16).

## Palette

| Token | Value | Use |
|---|---|---|
| `--rgb-dark` | `13, 8, 38` | Ink / dark surfaces (deep purple-navy) |
| `--rgb-light` | `248, 245, 242` | Paper / light surfaces (warm off-white) |
| `--rgb-pink` | `255, 138, 255` | Primary accent |
| `--rgb-pink-dark` | `237, 76, 200` | Accent hover/strong |
| `--rgb-pink-light` | `255, 190, 255` | Accent subtle |

Registry-specific extensions (not on omacon.org, needed here): success green,
warning amber, danger red for security states (quarantined / yanked / revoked).
Keep them desaturated so pink stays the only loud color.

## Type

- Sans: **Clash Grotesk** (400 / 500 / 600) — headings, UI, buttons.
- Mono: **JetBrains Mono** (400 / 700 / 800) — code, plugin ids, versions, checksums.
- Fluid base size: `max(0.75rem, 1.1875vw)`; medium `135%`, large `225%`.
- Line heights: 1.5 default, 1.2 tight (headings), 2.2 loose.

## Texture & motion

- Noise PNG overlays on both dark and light surfaces (`noise-dark.png` / `noise-light.png`, tiled at 20%).
- Easing: `cubic-bezier(0.19, 1, 0.22, 1)` at 0.25s (fast) / 0.75s (slow).
- Hairline borders: `max(1px, 0.0625em)` solid, plus 1px offset box-shadow "double rule".

## Components

- Buttons: filled dark (or light on dark), `border-radius: 0.6em`, weight 600,
  UPPERCASE, hover inverts or goes pink.
- Sticky section anchors that turn pink when stuck.
- Spacing scale: 1 / 1.5 / 2 / 3 / 4 / 5 em.

## Voice

Confident, playful, anti-corporate ("The vibes around Linux are changing",
"Coffee strong enough to compile a kernel"). Short declarative sentences.
Security copy stays plain-spoken, never scary-legal.

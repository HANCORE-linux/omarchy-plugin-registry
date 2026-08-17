---
version: alpha
name: Omacom
description: |
  Omacom's design system, distilled from the OMACON brand (omacon.org): warm paper canvas with
  deep space-indigo ink, neon pink as the only signal color, monospace body copy set in
  JetBrains Mono, and Clash Grotesk display type at calm weights. Hairline ink borders instead
  of gray dividers, noise texture instead of gradients, diamond bullets, dotted pink underlines,
  and a magenta glow reserved for hero moments. The voice is confident, punchy, and a little
  irreverent — technical depth without the academic pretense. Never generic SaaS, never
  corporate slideware.

mosaic:
  mode: auto                          # both modes are first-class: paper by day, ink by night
  colors:
    light:
      bg: "#F8F5F2"                   # paper
      surface: "#FFFFFF"
      code-bg: "#F3EDF2"
      text: "#0D0826"                 # ink
      muted: "rgba(13, 8, 38, 0.6)"
      accent: "#ED4CC8"               # magenta — pink #FF8AFF fails contrast on paper
      border: "rgba(13, 8, 38, 0.3)"
      success: "#237A59"
      warning: "#9A6A1D"
      danger: "#C23232"
      info: "#4D5BC9"
    dark:
      bg: "#0D0826"                   # ink — the logo's home surface
      surface: "#110C2E"              # a whisper above ink — hairlines carry structure, not lift
      code-bg: "#09051D"              # recessed below ink, like a terminal inset
      text: "#F8F5F2"                 # paper
      muted: "rgba(248, 245, 242, 0.68)"
      accent: "#FF8AFF"               # bright pink comes out at night
      border: "rgba(248, 245, 242, 0.28)"
      success: "#3DBD8C"
      warning: "#EFB35A"
      danger: "#E96A6A"
      info: "#8B96F0"
  chart:
    - "#ED4CC8"
    - "#6E7BE8"
    - "#2EA879"
    - "#E8A33D"
    - "#8A5FB8"
    - "#4E9BB8"

colors:
  # Spec role aliases — agents and the viewer key off these
  primary: "#ED4CC8"                  # Magenta — the working accent on light surfaces
  secondary: "#0D0826"                # Ink — deep space indigo

  # Brand palette (verbatim from omacon.org root.css)
  ink: "#0D0826"                      # --color-dark  rgb(13, 8, 38)
  paper: "#F8F5F2"                    # --color-light rgb(248, 245, 242)
  pink: "#FF8AFF"                     # --color-pink — nav, links, bullets on dark
  magenta: "#ED4CC8"                  # --color-pink-dark — glow, accent on light
  pink-pale: "#FFBEFF"                # --color-pink-light — glowing strokes on dark

  # Surfaces
  canvas: "#F8F5F2"
  canvas-dark: "#0D0826"
  surface: "#FFFFFF"
  surface-tint: "#F3EDF2"             # paper warmed toward pink
  surface-dark: "#110C2E"             # ink lifted a whisper — never a lighter blue panel
  surface-dark-elevated: "#161238"

  # Lines — hairlines are INK, not gray (signature move)
  hairline: "rgba(13, 8, 38, 0.9)"
  hairline-soft: "rgba(13, 8, 38, 0.18)"
  hairline-on-dark: "rgba(248, 245, 242, 0.9)"
  hairline-on-dark-soft: "rgba(248, 245, 242, 0.2)"

  # Text
  text: "#0D0826"
  text-soft: "rgba(13, 8, 38, 0.75)"
  text-muted: "rgba(13, 8, 38, 0.55)"
  text-inverse: "#F8F5F2"
  text-inverse-soft: "rgba(248, 245, 242, 0.75)"

  # Semantic (extensions — the brand palette defines none; these are tuned to sit
  # in the indigo/pink world. Danger is a true red so it never reads as brand pink.)
  success: "#2EA879"
  warning: "#E8A33D"
  danger: "#E04848"
  info: "#6E7BE8"

charts:
  # Categorical order for series — magenta leads, then cool/warm alternation.
  categorical:
    - "#ED4CC8"                       # magenta
    - "#6E7BE8"                       # periwinkle
    - "#2EA879"                       # emerald
    - "#E8A33D"                       # amber
    - "#8A5FB8"                       # violet
    - "#4E9BB8"                       # steel teal
  grid-on-light: "rgba(13, 8, 38, 0.12)"
  grid-on-dark: "rgba(248, 245, 242, 0.14)"

shadows:
  rule: "0 1px 0 #0D0826"                              # 1px offset underline-shadow, from the site
  rule-on-dark: "0 1px 0 #F8F5F2"
  glow: "0 0 14px rgba(237, 76, 200, 0.8), 0 0 26px rgba(237, 76, 200, 0.6)"   # neon logo glow
  glow-soft: "0 0 14px rgba(237, 76, 200, 0.5), 0 0 26px rgba(237, 76, 200, 0.3)"

typography:
  display-hero:
    fontFamily: "'Clash Grotesk', 'Space Grotesk', ui-sans-serif, system-ui, sans-serif"
    fontSize: 64px
    fontWeight: 500
    lineHeight: 1.1
    letterSpacing: -0.5px
  display-lg:
    fontFamily: "'Clash Grotesk', 'Space Grotesk', ui-sans-serif, system-ui, sans-serif"
    fontSize: 44px
    fontWeight: 400
    lineHeight: 1.2
    letterSpacing: -0.3px
  heading-xl:
    fontFamily: "'Clash Grotesk', 'Space Grotesk', ui-sans-serif, system-ui, sans-serif"
    fontSize: 34px
    fontWeight: 500
    lineHeight: 1.2
  heading-lg:
    fontFamily: "'Clash Grotesk', 'Space Grotesk', ui-sans-serif, system-ui, sans-serif"
    fontSize: 27px
    fontWeight: 500
    lineHeight: 1.2
  heading-md:
    fontFamily: "'Clash Grotesk', 'Space Grotesk', ui-sans-serif, system-ui, sans-serif"
    fontSize: 21px
    fontWeight: 600
    lineHeight: 1.25
  heading-sm:
    fontFamily: "'JetBrains Mono', ui-monospace, 'SFMono-Regular', monospace"
    fontSize: 16px
    fontWeight: 700
    lineHeight: 1.3
  body-lg:
    fontFamily: "'JetBrains Mono', ui-monospace, 'SFMono-Regular', monospace"
    fontSize: 17px
    fontWeight: 400
    lineHeight: 1.6
  body-md:
    fontFamily: "'JetBrains Mono', ui-monospace, 'SFMono-Regular', monospace"
    fontSize: 15px
    fontWeight: 400
    lineHeight: 1.55
  body-strong:
    fontFamily: "'JetBrains Mono', ui-monospace, 'SFMono-Regular', monospace"
    fontSize: 15px
    fontWeight: 700
    lineHeight: 1.55
  body-sm:
    fontFamily: "'JetBrains Mono', ui-monospace, 'SFMono-Regular', monospace"
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.5
  statement:
    fontFamily: "'JetBrains Mono', ui-monospace, 'SFMono-Regular', monospace"
    fontSize: 17px
    fontWeight: 400
    lineHeight: 2.2
  eyebrow:
    fontFamily: "'JetBrains Mono', ui-monospace, 'SFMono-Regular', monospace"
    fontSize: 12px
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: 0.5px
    textTransform: uppercase
  button:
    fontFamily: "'JetBrains Mono', ui-monospace, 'SFMono-Regular', monospace"
    fontSize: 13px
    fontWeight: 600
    lineHeight: 1
    letterSpacing: 0.5px
    textTransform: uppercase
  stat:
    fontFamily: "'Clash Grotesk', 'Space Grotesk', ui-sans-serif, system-ui, sans-serif"
    fontSize: 44px
    fontWeight: 500
    lineHeight: 1

rounded:
  none: 0px
  sm: 4px
  md: 8px
  card: 0px                            # cards and sections are square, hairline-ruled
  button: 10px                         # ~0.6em — the only rounded element on the site
  pill: 9999px

spacing:
  xs: 8px
  sm: 12px
  md: 16px
  lg: 24px
  xl: 32px
  xxl: 48px
  section: 64px
  section-lg: 96px
  container-max: 1100px

motion:
  fast: "0.25s cubic-bezier(0.19, 1, 0.22, 1)"
  slow: "0.75s cubic-bezier(0.19, 1, 0.22, 1)"

components:
  page-shell:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.text}"
    typography: "{typography.body-md}"
  section-dark:
    backgroundColor: "{colors.canvas-dark}"
    textColor: "{colors.text-inverse}"
    padding: "{spacing.section} 0"
  section-rule:
    borderTop: "1px solid {colors.hairline}"
    boxShadow: "{shadows.rule}"
  hero-light:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.text}"
    typography: "{typography.display-hero}"
  hero-dark:
    backgroundColor: "{colors.canvas-dark}"
    textColor: "{colors.text-inverse}"
    typography: "{typography.display-hero}"
  hero-kicker:
    textColor: "{colors.magenta}"
    typography: "{typography.eyebrow}"
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    typography: "{typography.button}"
    rounded: "{rounded.button}"
    padding: "14px 18px"
  button-primary-hover:
    backgroundColor: "{colors.pink}"
    textColor: "{colors.ink}"
  button-on-dark:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.button}"
    rounded: "{rounded.button}"
    padding: "14px 18px"
  card:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.text}"
    typography: "{typography.body-md}"
    rounded: "{rounded.card}"
    padding: "{spacing.xl}"
    border: "1px solid {colors.hairline}"
  card-dark:
    backgroundColor: "{colors.canvas-dark}"
    textColor: "{colors.text-inverse}"
    rounded: "{rounded.card}"
    padding: "{spacing.xl}"
    border: "1px solid {colors.hairline-on-dark}"
  stat-card:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.text}"
    typography: "{typography.stat}"
    rounded: "{rounded.card}"
    padding: "{spacing.lg}"
    border: "1px solid {colors.hairline}"
  badge:
    backgroundColor: "rgba(237, 76, 200, 0.12)"
    textColor: "{colors.magenta}"
    typography: "{typography.eyebrow}"
    rounded: "{rounded.pill}"
    padding: "5px 12px"
  badge-on-dark:
    backgroundColor: "rgba(255, 138, 255, 0.16)"
    textColor: "{colors.pink}"
    typography: "{typography.eyebrow}"
    rounded: "{rounded.pill}"
    padding: "5px 12px"
  term-underline:
    textDecoration: "none"
    backgroundImage: "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='4' height='4' viewBox='0 0 4 4'%3E%3Cline x1='1' y1='2' x2='4' y2='2' stroke='%23ED4CC8' stroke-width='2' stroke-linecap='round' stroke-dasharray='0 4'/%3E%3C/svg%3E\")"
    backgroundRepeat: "repeat-x"
    backgroundPosition: "0 100%"
    backgroundSize: "0.4em 0.4em"
    paddingBottom: "0.4em"
  list-bullet:
    content: "◆"
    textColor: "{colors.magenta}"
---

# Omacom Design System

The default design context for Omacom-branded artifacts, sites, tools, and AI-generated UI:
the company behind Omarchy, plugins.omarchy.org, and OMACON. Machine-readable tokens live in
the front matter; the rules and taste live below. Source of truth for the brand feel is
[omacon.org](https://www.omacon.org/) — warm paper, space-indigo ink, neon pink, monospace body.

When a project ships its own newer brand source (a project DESIGN.md, an explicit brief),
that wins. Otherwise, this is the baseline for anything under the `omacom` namespace.
The reference implementation of the brand is the OMACON site source:
[github.com/omacom-io/omacon-site](https://github.com/omacom-io/omacon-site).

## Brand Mark

The Omacom logo is three glowing geometric glyphs in a row — **circle · square · diamond** —
with each shape *knocked out* of its overlapping neighbor: the square's left edge is carved
concave by the circle, its right edge is notched by the diamond's tip, and the diamond loses
its left point to the square. The knockouts are the mark; never redraw it as three separate
whole shapes butted together.

Canonical static geometry (the end state of the site's header animation, verbatim from
`assets/js/modules/header.js`):

```svg
<svg viewBox="0 0 1103 453" xmlns="http://www.w3.org/2000/svg" fill="currentColor">
  <defs>
    <mask id="omk-c">
      <rect x="-500" y="-500" width="2500" height="1500" fill="white"/>
      <rect x="448.6" y="105.2" width="223.7" height="242.7" fill="black"/>
    </mask>
    <mask id="omk-r">
      <rect x="-500" y="-500" width="2500" height="1500" fill="white"/>
      <circle cx="362" cy="226.5" r="132" fill="black"/>
      <polygon points="741,94.48 873.02,226.5 741,358.52 608.98,226.5" fill="black"/>
    </mask>
    <mask id="omk-d">
      <rect x="-500" y="-500" width="2500" height="1500" fill="white"/>
      <rect x="448.6" y="105.2" width="223.7" height="242.7" fill="black"/>
    </mask>
  </defs>
  <circle cx="362" cy="226.5" r="132" mask="url(#omk-c)"/>
  <rect x="448.6" y="105.2" width="223.7" height="242.7" mask="url(#omk-r)"/>
  <polygon points="741,94.48 873.02,226.5 741,358.52 608.98,226.5" mask="url(#omk-d)"/>
</svg>
```

Usage rules:

- **Home surface is ink/black, always glowing.** Fill with Pink `#FF8AFF` (or Pale Pink
  `#FFBEFF` for the delicate treatment) and apply the neon glow exactly as the site does:
  `filter: drop-shadow(0 0 0.875em rgba(237,76,200,0.8)) drop-shadow(0 0 1.625em rgba(237,76,200,0.6))`.
  On paper, use it small and flat in Magenta `#ED4CC8` or Ink — no glow on light surfaces.
- **Single color only.** The three glyphs always share one fill (`currentColor`); never
  multicolor the shapes, never outline them.
- **Motion is part of the mark**: the site draws the shapes converging from off-canvas over
  1.5s with an ease-in-out cubic. Reproduce that behavior (or keep it static) — don't invent
  other logo animations.
- **The glyphs may live alone as motifs.** The diamond already serves as the list bullet `◆`;
  circle/square/diamond make natural section markers, chart glyphs, or loading states. Motif
  use is flat brand-pink, without the knockouts and without the glow.
- Favicon / mask-icon color is Ink `#0D0826` (per the site's `mask-icon`).

## Design Thesis

Omacom should feel like **a love letter to computers, typeset by someone with taste**: terminal
culture elevated to print quality. The tension that makes it work is monospace body text — the
font of code and config files — set on warm paper with editorial discipline, then hit sparingly
with a neon pink that glows like a CRT in a dark room.

Think: zine meets man page. Hairline rules, generous whitespace, calm display type, one loud
color. Not: SaaS dashboard, pastel startup template, hacker-green terminal cosplay, or a
corporate deck wearing a Linux t-shirt.

## Core Principles

1. **Paper first, ink always.** The default surface is warm paper (`#F8F5F2`) with space-indigo
   ink (`#0D0826`). Dark sections invert the same pair — never introduce a third neutral world.
2. **Pink is a signal, not a coat of paint.** One accent family does all accent work: links,
   bullets, key terms, active states, glows. If everything is pink, nothing is.
3. **Monospace is the voice.** Body copy, labels, buttons, and metadata are JetBrains Mono.
   Display type (Clash Grotesk) appears only at heading scale, and at *calm* weights — 400–500,
   never black/900. Restraint in the headings is what lets the mono body feel intentional.
4. **Rules, not shadows.** Structure comes from 1px ink hairlines and ruled section borders.
   No soft gray drop shadows, no elevation theater. The one permitted shadow is the magenta glow,
   reserved for hero/logo moments.
5. **Square by default.** Cards and sections have square corners. Only buttons and pills are
   rounded. Texture comes from subtle noise, never gradients.
6. **Signature details carry the brand**: diamond `◆` list bullets in magenta; dotted magenta
   underlines beneath defined terms; uppercase mono eyebrows; sticky section headers that flood
   pink when active.

## Color Usage

- **Two modes, one world.** Light mode is paper-with-ink; dark mode is ink-with-paper — the
  same two colors trading places, exactly like the site's alternating sections. Both are
  first-class (`mosaic.mode: auto`): documents render light or dark with the viewer, and dark
  is where the logo glows. Never introduce a third neutral scheme for either mode.
- **The accent swaps with the mode**: Magenta `#ED4CC8` on paper, Pink `#FF8AFF` on ink.
  Semantic colors also carry per-mode values (`mosaic.colors.*`) — deeper on paper for
  contrast, lifted on ink; the mid-tone base tokens are for charts and non-text fills.
- **On paper**: text is ink; the accent is **Magenta `#ED4CC8`** (bright Pink `#FF8AFF` fails
  contrast on light backgrounds — never use it for text on paper).
- **On ink**: text is paper; the accent is **Pink `#FF8AFF`**, with **Pale Pink `#FFBEFF`** for
  glowing strokes and delicate lines. Magenta becomes the glow color (`shadows.glow`).
- **Semantic colors** (success/warning/danger/info) are pragmatic extensions for callouts,
  status pills, and charts — keep them at UI scale, never as brand moments. Danger is a true red
  (`#E04848`) precisely so it can never be confused with brand pink.
- **Charts** lead with magenta, then alternate cool/warm from `charts.categorical`. Grid lines
  are transparent ink (or transparent paper on dark), matching the hairline system.

## Typography

- **Clash Grotesk** — headings and stats only. Weights 400–600. Tight line-height (~1.2).
  Fallback: Space Grotesk, then system sans.
- **JetBrains Mono** — everything else: body, lists, tables, captions, eyebrows, buttons.
  Body sits at 15px/1.55; pull-quote "statements" open up to 2.2 line-height and deserve
  their own space.
- Uppercase is reserved for small mono labels (eyebrows, buttons, footer legal). Bold (700–800)
  belongs to mono emphasis, not display type.

## Voice & Copy

Confident, punchy, a little irreverent. Short declaratives. Technical depth without academic
pretense; wit without smugness. House flavor, from the source material: "Strong opinions,
loosely held." "Coffee strong enough to compile a kernel." Write like someone who loves
computers and respects the reader's time.

- Lead with the point. No throat-clearing, no "in today's fast-paced world."
- Name things plainly: say what a feature does, not what it "empowers."
- A single playful line per section beats constant jokes.
- Optional sign-off flourish, sparingly, in footers: katakana brand mark (オマコム) in the
  legal line, in the footer pink bar style.

## Do / Don't

**Do**: warm paper backgrounds · ink hairlines with 1px offset rule-shadows · magenta diamond
bullets · dotted term underlines · calm big headings · mono body · pink flood on hover/active ·
noise texture on dark sections · the neon glow, once per page, where it counts.

**Don't**: gradients · gray drop shadows · rounded cards · Pink `#FF8AFF` text on paper ·
heavy display weights · more than one accent hue in a layout · hacker-green or Matrix clichés ·
corporate stock imagery · timid gray-on-gray minimalism.


---
version: alpha
name: Selektos — The Auditor's Ledger
description: Continuous-feed greenbar stock and double-entry ledger grammar for a precise, local-first database workspace.
colors:
  primary: "#1c3b2a"
  primary-dark: "#12291d"
  secondary: "#bfd4b3"
  secondary-soft: "#d5e2cb"
  tertiary: "#a32a1b"
  neutral-paper: "#e4e8df"
  neutral-paper-edge: "#dadfd3"
  neutral-hole: "#a8b0a2"
  neutral-ink: "#14160f"
  neutral-ink-secondary: "#4a5245"
  neutral-ink-tertiary: "#5f6759"
  neutral-rule: "rgba(20, 22, 15, .26)"
  neutral-rule-hair: "rgba(20, 22, 15, .14)"
typography:
  display-hero:
    fontFamily: "\"Big Shoulders\", \"Haettenschweiler\", \"Arial Narrow\", sans-serif"
    fontSize: "clamp(3.4rem, 9.6vw, 6.6rem)"
    fontWeight: 800
    lineHeight: 0.855
    letterSpacing: "0.004em"
  display-section:
    fontFamily: "\"Big Shoulders\", \"Haettenschweiler\", \"Arial Narrow\", sans-serif"
    fontSize: "clamp(2.3rem, 5.1vw, 4.1rem)"
    fontWeight: 700
    lineHeight: 0.94
    letterSpacing: "0.006em"
  body:
    fontFamily: "\"Archivo\", ui-sans-serif, system-ui, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 400
    lineHeight: 1.62
  body-lede:
    fontFamily: "\"Archivo\", ui-sans-serif, system-ui, sans-serif"
    fontSize: "clamp(1.08rem, 1.34vw, 1.32rem)"
    fontWeight: 400
    lineHeight: 1.54
  title:
    fontFamily: "\"Archivo\", ui-sans-serif, system-ui, sans-serif"
    fontSize: "1.02rem"
    fontWeight: 700
    lineHeight: 1.2
  mono-data:
    fontFamily: "\"Sometype Mono\", ui-monospace, \"SF Mono\", Menlo, monospace"
    fontSize: "0.83rem"
    fontWeight: 400
    lineHeight: 1.85
  mono-label:
    fontFamily: "\"Sometype Mono\", ui-monospace, \"SF Mono\", Menlo, monospace"
    fontSize: "0.76rem"
    fontWeight: 500
    lineHeight: 1
    letterSpacing: "0.11em"
rounded:
  none: "0px"
spacing:
  feed-margin: "clamp(20px, 3vw, 44px)"
  content-gutter: "clamp(18px, 4.4vw, 64px)"
  compact-control-x: "0.7rem"
  compact-control-y: "0.38rem"
  ledger-cell-x: "0.8rem"
  ledger-cell-y: "0.72rem"
components:
  source-button:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.neutral-paper}"
    typography: "{typography.mono-label}"
    rounded: "{rounded.none}"
    padding: "0.46rem 0.78rem"
  source-button-hover:
    backgroundColor: "{colors.primary-dark}"
  copy-button:
    backgroundColor: "transparent"
    textColor: "{colors.primary}"
    typography: "{typography.mono-label}"
    rounded: "{rounded.none}"
    padding: "0.38rem 0.7rem"
  copy-button-hover:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.neutral-paper}"
  rights-tag:
    backgroundColor: "transparent"
    textColor: "{colors.primary}"
    typography: "{typography.mono-label}"
    rounded: "{rounded.none}"
    padding: "0.16rem 0.45rem"
  ledger-row:
    backgroundColor: "{colors.secondary}"
    textColor: "{colors.neutral-ink}"
    rounded: "{rounded.none}"
    padding: "0.72rem 0.8rem"
---

<!-- impeccable:design-schema 1 -->

# Design System: Selektos — The Auditor's Ledger

## Overview

**Creative North Star: "The Auditor's Ledger"**

Selektos uses the material language of greenbar continuous-feed machine stock organized by double-entry ledger grammar. It should feel institutional, exact, inspectable, and physical without becoming nostalgic decoration: data is posted into ruled records, state is printed in place, and security boundaries are shown as accounting facts.

The system is dense but orderly. Cool paper, dark ledger fields, hairline rules, tabular figures, and running folio feet carry hierarchy without cards or ornamental chrome. The visual world supports the product's local-first and read-only posture by making custody, rights, and bounded results visible rather than merely promising them.

Surface-specific narrative belongs in each surface brief. The current landing page's folio sequence, build-from-source entry, and side-by-side refusal example are expressions of this system, not mandatory compositions for every future Selektos surface.

**Key Characteristics:**
- Continuous-feed paper with full-height sprocket margins.
- Edge-to-edge ruled columns, paired hairlines, and alternating greenbar rows.
- Condensed institutional display type, workhorse sans prose, and line-printer mono data.
- Flat tonal hierarchy with no floating card layer.
- Audit red reserved for refusal, critical focus, and command prompts.
- Running folio feet in place of decorative kickers.

## Colors

The palette is a cool, low-chroma paper-and-ink system led by ledger green, with red used as a scarce audit mark.

### Primary
- **Ledger Green:** The structural field color for mastheads, dark folios, selected records, primary controls, and browser chrome.
- **Dark Ledger:** The deeper hover and code-surface color used when Ledger Green needs a second tonal level.

### Secondary
- **Greenbar Stock:** The alternating ledger band, dark-field accent, and positive read state.
- **Soft Greenbar:** A quiet section ground, inline-code fill, and scrollbar track.

### Tertiary
- **Audit Red:** Reserved for refusal stamps, mutating SQL strings, warning tags, command prompts, and the global focus ring.

### Neutral
- **Cool Paper:** The page ground and light text knocked out of dark fields.
- **Paper Edge:** The continuous-feed margin stock.
- **Sprocket Hole:** The repeating feed-hole mark.
- **Letterpress Ink:** Primary text and hard rules.
- **Secondary Ink:** Supporting copy, captions, and ledger headings.
- **Tertiary Ink:** Folio numbers, low-priority metadata, and subdued figures.
- **Rule / Hairline Rule:** Transparent Letterpress Ink used for regular and quiet dividers.

### Named Rules

**The Audit Red Rule.** Red is evidence of refusal, risk, focus, or a command prompt; it is never a general decorative accent.

**The Paper Is a Surface Rule.** Cool Paper is the default canvas. Greenbar and Ledger Green create functional regions, not detached cards.

**The Greenbar Exception Rule.** Repeating gradients are permitted only to reproduce functional greenbar stock; radial gradients are permitted only for sprocket holes.

## Typography

**Display Font:** Big Shoulders, self-hosted variable font, with Haettenschweiler and Arial Narrow fallbacks
**Body Font:** Archivo, self-hosted variable font, with system sans fallbacks
**Label/Mono Font:** Sometype Mono, self-hosted variable font, with SF Mono and Menlo fallbacks

**Character:** Condensed caps provide institutional authority, Archivo keeps explanation direct and readable, and Sometype Mono makes every identifier, figure, command, and ledger label feel posted rather than decorated.

### Hierarchy
- **Display Hero:** Extra-bold condensed uppercase, tightly led and fluidly scaled; use for a single dominant declaration.
- **Section Headline:** Bold condensed uppercase with balanced wrapping and a paired rule above.
- **Title:** Bold Archivo for row descriptions and procedural headings.
- **Body:** Archivo at a comfortable reading rhythm; keep explanatory measures around 62–66 characters.
- **Lede:** A modest fluid enlargement of body copy, not a separate display voice.
- **Mono Data:** Sometype Mono for commands, SQL, identifiers, values, paths, and table content; numerals are tabular.
- **Mono Label:** Small uppercase Sometype Mono with wide tracking for column heads, folios, statuses, and metadata.

### Named Rules

**The Three-Voice Rule.** Big Shoulders declares, Archivo explains, and Sometype Mono records; do not exchange their jobs.

**The Posted Figure Rule.** Every figure, identifier, command, and machine state uses the mono voice with tabular numerals.

## Layout

The page is one continuous sheet bounded by responsive feed margins and a centered maximum body width of 1360px. Content gutters are fluid, and major regions are formed by borders and columns that meet edge to edge. The principal desktop split uses a 1.32:1 relationship; paired proof regions use equal columns; procedural content uses a near-even 1.05:1 split.

Spacing is fluid at the section level and compact inside records. Dense ledger rows typically use roughly 0.7–0.8rem horizontal and 0.4–0.95rem vertical padding, while section arrivals use clamps spanning approximately 1.8–5rem. Reading measure is capped at 66ch.

At 1080px, complex three-column workspace evidence reduces to two columns and moves inspection data below. At 900px, the masthead wraps, the index remains visible on its own ruled row, paired ledgers stack, and sticky instructions become static. At 700px, workspace regions linearize, schedules become labeled ledger records instead of horizontally compressed tables, facts collapse to one column, and command text wraps. At 420px, lower-priority folio metadata is selectively omitted, but navigation does not disappear.

**The Continuous Sheet Rule.** New regions extend the ledger through shared rules and tonal bands; they do not become isolated card islands.

**The Responsive Record Rule.** Tabular structures stack into readable records on narrow screens while preserving order, labels, and dividers.

## Elevation & Depth

The system is flat. Hierarchy comes from paper tone, greenbar banding, dark ledger fields, hard borders, hairline rules, overprinting, and column structure—not drop shadows or floating surfaces. The inset lines inside audit stamps simulate a rubber-stamp border and are not an elevation token.

**The No Decorative Shadow Rule.** Never use shadows to lift panels, buttons, or navigation. If hierarchy is unclear, strengthen ruling, tone, or spacing.

## Shapes

Rectangular surfaces and controls are square-cornered. One-pixel rules form the dominant geometry; paired rules use two one-pixel lines separated within a four-pixel band. Dashed vertical rules separate the feed margins from the printable sheet.

Circles are functional and small: sprocket holes, stamp separator dots, or icon geometry. The Selektos app icon may retain its native five-pixel image radius, but that exception does not establish a rounded-surface language.

**The Square Ledger Rule.** Containers, controls, tags, code panels, and table regions use zero radius.

## Components

### Buttons
- **Shape:** Square ledger control with a one-pixel border.
- **Solid:** Ledger Green field with Cool Paper text; Dark Ledger on hover.
- **Outline:** Transparent paper field with Ledger Green border and text; invert to Ledger Green and Cool Paper on hover or copied state.
- **Focus:** A two-pixel Audit Red outline offset by three pixels; on dark folios use Greenbar Stock.
- **Motion:** Color changes use the shared emphasized ease over 160–180ms. Buttons do not lift, scale, or cast shadows.

### Tags
- **Style:** Square, transparent, one-pixel outlined labels set in uppercase mono.
- **State:** Standard rights use Ledger Green; warnings use Audit Red. Tags label state but never replace explanatory copy.

### Ruled Tables and Records
- **Style:** Collapsed one-pixel rules, compact cells, mono figures, and alternating Greenbar Stock rows.
- **Headers:** Small tracked uppercase mono; dark table headers reverse Cool Paper out of Ledger Green.
- **Selection:** Use a solid Ledger Green row or paired inset Audit Red rules, depending on context.
- **Responsive:** Convert schedules into vertically stacked records below 700px rather than shrinking the type.

### Ledger Posting
- **Style:** A numbered entry column, description column, and optional rights column joined by rules.
- **Use:** Primary actions and consequential records may be posted as ledger entries when the action itself is evidence.
- **Mobile:** Remove the amount column before compromising command readability.

### Audit Stamp
- **Style:** Audit Red double-inset border, uppercase Archivo, slight rotation, and multiply overprint on paper.
- **Motion:** The large refusal stamp may strike once using the emphasized ease over 620ms. Guard it with `prefers-reduced-motion`; reduced motion resolves immediately.
- **Use:** Only for consequential refusal or audit outcomes, never as a decorative badge.

### Navigation
- **Style:** Plain text links with mono folio numbers and underline/border emphasis on hover.
- **Responsive:** Wrap the index onto a ruled row; do not replace it with hidden navigation solely to preserve a desktop silhouette.

### Browser Surfaces
- **Selection:** Ledger Green with Cool Paper; on dark folios, Greenbar Stock with Dark Ledger.
- **Scrollbars:** Thin, with Ledger Green thumbs and Soft Greenbar tracks.
- **Scrollable Regions:** Become keyboard-focusable labeled regions only when overflow actually exists.

## Do's and Don'ts

### Do:
- **Do** build hierarchy from ruling, banding, dense records, and tonal contrast.
- **Do** keep display type condensed and uppercase, prose readable, and all figures and commands monospaced.
- **Do** preserve full-height sprocket margins and the continuous-sheet reading model on authored web surfaces.
- **Do** keep the masthead index visible by wrapping it at narrower widths.
- **Do** theme selection, scrollbars, focus, print, and reduced-motion behavior as part of the world.
- **Do** use running folio feet for section identity and pagination.

### Don't:
- **Don't** introduce cards, pills, rounded containers, glass panels, or floating window chrome.
- **Don't** use decorative gradients; only functional greenbar stripes and sprocket-hole radials belong.
- **Don't** use decorative drop shadows. Audit-stamp inset registration lines are the narrow functional exception.
- **Don't** use Audit Red as a broad brand fill or routine hover color.
- **Don't** introduce eyebrow or kicker copy above headings; the ledger's running folio system already carries orientation.
- **Don't** use generic glyph characters as interface icons; use authored inline SVG where an icon is necessary.
- **Don't** promote a landing-page folio, claim, or proof sequence into a mandatory global component.

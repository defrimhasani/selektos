# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

The shipped product is a native macOS app (SwiftUI + AppKit). The design surface held in this
repository is `docs/`, the project's GitHub Pages marketing site, which is web.

## Users

**Primary (confirmed):** macOS developers who work with PostgreSQL daily and want a genuinely native
client rather than an Electron wrapper. They arrive from a repository link, a share, or a search,
evaluate in minutes, and decide whether to spend the effort to build it.

Secondary audiences exist in the feature set — Cloudflare D1 / edge developers, and developers wiring
AI agents to their own databases — but the page is written for the primary user above.

## Product Purpose

Selektos is a native macOS database workspace for PostgreSQL and Cloudflare D1, with a built-in
local MCP server so AI agents can query saved connections under explicit, read-only-by-default
limits. Success is a developer connecting to a real database and getting a useful answer without
leaving the app or handing credentials to a cloud service.

## Positioning

**Confirmed lead claim: the MCP server.** Other native macOS SQL clients exist; none of them is also
an MCP server that exposes *your saved connections* to a local AI agent with read-only enforcement at
three layers (conservative SQL validation, a read-only PostgreSQL transaction with
`default_transaction_read_only`, and discovery tools that are always read-only regardless of
configuration). Passwords stay in the macOS Keychain and are never exposed through MCP.

The supporting, non-copyable facts: real SwiftUI/AppKit (not a web view), and credentials that never
leave the machine.

## Operating Context

- Developers run this alongside a terminal, an editor, and an AI coding agent (Claude Desktop,
  Copilot, or similar MCP client) on the same machine.
- Cloudflare D1 access runs through the developer's own authenticated Wrangler CLI; Cloudflare tokens
  are managed by Wrangler and never read or stored by Selektos.
- Agent access is configured by pasting an `mcp.json` snippet into an MCP client, then restarting
  that client so it refreshes its tool list.
- The website is a static GitHub Pages site served from `docs/` on the default branch. No build step,
  no bundler, no server: whatever is committed is what ships.

## Capabilities and Constraints

Confirmed from the codebase and README:

- User-defined workspaces persisted in Application Support; multiple PostgreSQL connections each.
- Passwords in macOS Keychain. TLS disable / prefer / require modes.
- Live schema and table discovery; persistent query tabs with a native AppKit editor.
- Per-tab database and schema focus; selecting a schema sets `search_path` to that schema then
  `public`. Postgres-internal schemas are hidden from the picker.
- Query execution and cancellation; dynamic result grids for arbitrary result shapes; row inspector.
- Cloudflare D1 discovery and remote query execution via `wrangler d1 execute --remote --json`.
- Local stdio MCP server exposing `list_connections` plus four tools per saved connection
  (`list_tables_*`, `describe_table_*`, `preview_table_*`, `query_*`), with a configurable row cap.
- Result display is capped at 10,000 rows by default to keep the UI responsive.
- Requires macOS 15+.
- Direct-distribution pipeline exists (`make dist`, `make dist-universal`, DMG + ZIP, ad-hoc signed
  by default, notarization supported).

**Undecided / not true yet — must not be claimed:**

- No published GitHub release exists. Confirmed primary action is **build from source**
  (`git clone` → `swift run Selektos`). A releases CTA would send visitors to an empty page.
- No license file in the repository. The site must not state a license.
- No pricing, no hosted service, no Windows or Linux build.

## Brand Commitments

- Name: **Selektos**. Published by **Pluto Labs**.
- Existing app icon: `Assets/SelektosIcon.svg` (editable source) and `Assets/SelektosIcon.png`.
- Canonical URLs: site `https://defrimhasani.github.io/selektos/`, repo
  `https://github.com/defrimhasani/selektos`.
- No other identity constraints were set; the user left visual direction open.

## Evidence on Hand

- The app icon, in editable SVG and PNG.
- The README, which is accurate and detailed — the strongest factual asset the project has.
- The folio 02 workspace view on the site is an HTML/CSS transcription of the interface with
  synthetic sample data, labelled as such in its caption. It is not a captured screenshot. The two
  earlier hand-drawn SVG previews (`workspace-preview.svg`, `mcp-settings-preview.svg`) were removed
  when the site was redesigned.

**Absences future work must not paper over:** no testimonials, no users, no customers, no press, no
download counts, no benchmarks, no GitHub stars (the repository has zero), no awards, no team page.
The repository is public but currently unstarred and undescribed. Any social proof on the page would
be fabricated.

## Product Principles

1. **Credentials stay on the machine.** Keychain for passwords, Wrangler for Cloudflare tokens.
   Nothing about a connection travels to a server the developer did not choose.
2. **Read-only is the default posture.** Agent power is opt-in, explicit, and reversible; the safe
   path is the one that requires no configuration.
3. **Native before convenient.** Real macOS behavior — AppKit text editing, a real Settings window,
   system theming — is worth more than cross-platform reach.
4. **Context is always explicit.** The developer can see which connection, database, and schema a
   query targets; nothing resolves by magic.
5. **Bounded by default.** Row caps and previews keep a desktop app responsive on databases that
   would otherwise drown it.

## Accessibility & Inclusion

No product-specific requirement was established by the user. Web work on `docs/` holds WCAG 2.2 AA as
its floor: keyboard-operable navigation, visible focus, honored `prefers-reduced-motion`, and text
contrast that passes at real rendered sizes.

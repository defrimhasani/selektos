# Selektos

A native macOS SQL client built with SwiftUI, AppKit, Security, and Swift concurrency. PostgreSQL transport is provided by PostgresNIO, while Cloudflare D1 access uses the authenticated Wrangler CLI.

## Open and run

Open `Package.swift` in Xcode, select the `Selektos` scheme, and run the app.

From Terminal:

```sh
swift run Selektos
```

## Current features

- User-defined workspaces persisted in Application Support
- Multiple PostgreSQL connections per workspace
- Password storage in macOS Keychain
- TLS disable, prefer, and require modes
- Live schema and table discovery
- Persistent query tabs with a native AppKit editor
- Per-tab database and schema focus from the editor toolbar
- Native Settings window for general behavior, appearance, workspaces, and connections
- Query execution and cancellation
- Dynamic result grids for arbitrary result shapes
- PostgreSQL error and execution status display
- Cloudflare D1 remote database discovery and query execution through Wrangler

Query result display is capped at 10,000 rows to keep the desktop UI responsive. Add a `LIMIT` clause when exploring large tables.

## Schema focus

Connecting as a superuser exposes every schema at once. The editor toolbar has **Database** and **Schema** dropdowns to narrow that down.

The schema choice is stored per query tab, so different tabs can target different schemas on the same connection. Selecting one sets the connection's `search_path` to that schema followed by `public`, meaning:

- unqualified names such as `SELECT * FROM orders` resolve in the focused schema first
- `public` stays reachable, so shared tables keep working
- fully qualified names such as `other_schema.orders` are unaffected

Choose **All schemas** to leave the server's default `search_path` untouched. Opening a table from the sidebar creates a tab already focused on that table's schema. Postgres-internal schemas (`pg_*`, `information_schema`) are hidden from the dropdown; query them by qualifying the name.

Switching database clears the schema focus for that connection's tabs, since schema names are database-scoped.

## Settings

Open **Selektos → Settings** or press `Command-,`.

- **General:** launch behavior, automatic metadata loading, result row limit, default query text, and state-file location
- **Appearance:** system/light/dark theme, live editor font size, line numbers, and inspector visibility
- **Workspaces:** create, activate, rename, and delete workspaces
- **Connections:** choose a workspace, then add, edit, or delete PostgreSQL and Cloudflare D1 connections

Preferences use macOS `UserDefaults`. Workspace/query state remains in `~/Library/Application Support/Selektos/workspaces.json`; PostgreSQL passwords remain in macOS Keychain.

## Cloudflare D1

Authenticate Wrangler before adding a D1 connection:

```sh
wrangler login
```

In the connection sheet, choose **Cloudflare D1**, leave the Wrangler executable as `wrangler`, and click **Discover**. Selektos automatically detects common global installations, including Homebrew, npm, and NVM. For a project-local install, provide the full path to its executable, typically `node_modules/.bin/wrangler`.

The app executes D1 queries remotely with `wrangler d1 execute --remote --json`. Cloudflare tokens are managed entirely by Wrangler and are not read or stored by Selektos.

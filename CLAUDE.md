# SiteSearch - working notes

Small macOS Tahoe app: user-configured keyword -> URL-template site search,
surfaced in Spotlight via App Intents. See README.md for the user-facing
story.

## Architecture

Model / storage:

- `Sources/Site.swift` - `Site` (id, keyword, name, template) + `SiteStore`,
  a stateless enum that reads/writes
  `~/Library/Application Support/SiteSearch/sites.json` on every call.
  Stateless on purpose: the intent may run in a background-launched app
  instance, so reading fresh from disk avoids stale-config bugs. Defaults
  carry hardcoded UUIDs (Spotlight caches entity ids - fresh-per-launch ids
  broke recents and pre-filled parameters). The file is hand-editable, so
  `id` is optional on disk: `load` fills a missing one into the raw document
  before decoding, derived from the entry's content (name-based UUID), so
  every process agrees on it and `Site`'s Codable stays the one description
  of the format. Unknown keys such as the old per-site `slot` are ignored.
  `save` throws; `mutate` propagates, so the MCP tools and the window report a
  write that did not land.
- `Sources/SiteEntity.swift` - `SiteEntity` and `BookmarkEntity` share
  everything through `SiteBackedEntity` (fields, favicon display) and
  `SiteBackedQuery` (`EnumerableEntityQuery` for the full dropdown,
  `EntityStringQuery` so the keyword alias matches during type-to-filter); each
  concrete type only names its list and fallback glyph. Entity `id` is the
  Site's UUID string (stable across renames), keyword is the subtitle.
  `filter(_:matching:)` is the pure predicate behind `entities(matching:)` -
  name substring OR keyword prefix. A refactor here must leave
  `Metadata.appintents` unchanged: compare it before and after (the extractor
  may reorder `resolvableInputTypes`; that is not a change).
- `Sources/SearchSiteIntent.swift` - the search intent: two parameters (site
  entity + query). `supportedModes: .background`
  (macOS 26 API) so the app never foregrounds; `perform()` opens the URL via
  `NSWorkspace.shared.open`. URL building lives in `SiteURL` (shared with the
  MCP tool): RFC 3986 unreserved chars only (`.urlQueryAllowed` would pass `&`,
  `=`, `+` through), `{query}` validation, and `SiteURL.webURL`, the one
  definition of an openable URL (http(s) with a host), which link inference
  and favicon origins use too. `SiteOps.uniqueKeyword` is the one keyword
  de-duplicator (import merge, Add Site's `LinkInference.draftSite`).
- `Sources/OpenBookmarkIntent.swift` - the bookmark intent: one parameter, no
  query. Separate from the search intent because Spotlight cannot vary a
  `parameterSummary` per selected entity; the header comment records the three
  single-action shapes tried and how each failed on 26.5. `BookmarkEntity`
  lives in `SiteEntity.swift` and is a distinct type on purpose - a dropdown
  comes from the entity's `defaultQuery`, so two lists means two types.

Config changes and agent access:

- `Sources/SiteOps.swift` - pure, intent-shaped operations (add one, update
  fields of one, remove one) plus `SiteOpError`. Never whole-list replacement:
  that is what let a stale snapshot clobber a concurrent write. Selectors
  accept an id or a keyword. Templates are validated with the same builder the
  search uses, so a site that stores cannot fail only at search time. Adding a
  duplicate keyword is an error here (an agent asked for `hn` and should be
  told), unlike import-merge which suffixes on purpose.
- `Sources/SiteURL.swift` - `SiteURL.resolve/build` + `SearchSiteError`,
  Foundation only, so the CLI can validate without importing AppIntents.
  A site's KIND is inferred from its template, not stored: with `{query}` it
  is a search, without it is a bookmark that opens as-is (`sb repo1`). One
  model and one keyword namespace, but two dropdowns - `Site.searches` /
  `Site.bookmarks` split the list per action, since an action whose summary
  demands a query cannot also serve entries that have nothing to substitute.
  `resolve` handles both; `build` stays strict for the search path. A search
  run with no query resolves to the bare search page rather than failing.
- `Sources/Favicon.swift` - fetches each site's icon FROM ITS OWN ORIGIN (a
  third-party favicon proxy would report every configured site to someone
  else), caching bytes at `icons/<site-uuid>/<origin>` so `sites.json` stays
  clean JSON. The origin in the key is what makes a slow fetch harmless: one
  for an origin the site has since left (window or MCP process) lands in that
  origin's file, never on the current icon. Tries `/favicon.ico`, then parses
  the page's `<link rel="...icon...">` tags with a regex - one attribute out
  of <head> does not justify an HTML parser. Every cache change goes through `Favicon.refresh(from:to:)`: a
  removed site or one whose origin moved loses its icon, a new or moved one is
  fetched, and `from: []` backfills (app launch, window open). Never on rename
  and never at draw time: `displayRepresentation` is synchronous, so a
  network call there would stall the Spotlight dropdown. The fetcher is
  injected so tests run offline. Verified live: Google/GitHub return `.ico`,
  hn.algolia.com falls through to a declared PNG, and NSImage decodes both.
- `Sources/MCPHandler.swift` - the MCP server as a pure function of (request,
  config URL), with an injectable `opener` so `search_site` is testable without
  launching a browser. Shared by both targets so the unit tests can reach it.
  `Tool` is the one tool table (exhaustive switches, so a listed tool cannot
  lack a schema or an implementation); `ToolCall` parses arguments once at the
  edge, and a present argument of the wrong type is an error, not an omitted
  field. Tool failures come back as results with `isError`, not JSON-RPC
  errors: the call worked, the operation did not, and the agent needs to read
  why. `serverInfo.version` is the bundle's `CFBundleShortVersionString`; the
  tool target links an Info.plist into its binary so it knows the version
  standalone too, and `MARKETING_VERSION` is project-wide in project.yml.
- `Sources/MCPMain/main.swift` - the stdio loop. EXCLUDED from the app target
  in project.yml (top-level code cannot coexist with the app's `@main`); built
  as the `sitesearch-mcp` tool target and copied into
  `Contents/MacOS/sitesearch-mcp` via a dependency `copy: destination:
  executables`. Note `embed: false` on that dependency silently suppresses the
  copy phase - do not add it back.

Quick keys:

- `Sources/QuickKeySync.swift` - registers exactly two quick keys, `ss` for
  search and `sb` for bookmarks, one per action (see the undocumented key
  below). Neither varies with the config: site keywords are filter text inside
  the entity dropdown, not registered abbreviations, so adding a site writes
  nothing here. Entries
  belonging to other apps are never touched, an abbreviation another app's
  action already claims is never stolen, and any per-site entry left behind by
  0.4.0-0.7.0 is pruned by the same "our prefix becomes exactly desired" rule.

Sharing:

- `Sources/SiteExchange.swift` - the `.sitesearch` format (JSON v1, no ids -
  the receiver mints its own so imports never collide with the sender's entity
  identifiers). The file is untrusted: `parse` runs every entry through
  `SiteOps.validate` and returns the rejects with reasons, which the import
  sheet lists. Merge skips entries whose (name, template) already exists and
  suffixes colliding keywords.
- `Sources/ShareSheets.swift` - export sheet (per-site checkboxes ->
  ShareLink / save panel) and import sheet (double-click a `.sitesearch` file,
  declared UTI `com.zamua.sitesearch.sites`).

UI:

- `Sources/ConfigView.swift` + `SiteSearchApp.swift` - plain SwiftUI window
  with an editable Table. `Sources/ConfigSync.swift` is its sync loop as one
  pure `handle(event) -> [effect]` (edited, saveDue, saved, saveFailed,
  polled, reloaded, imported, importFailed): the only place the shown list,
  baseline, stamp, save error and status message change. The view only
  forwards events (user edits come from the bindings and buttons, never from
  `onChange`, so absorbing disk is not mistaken for an edit) and performs
  effects (one save timer, the locked save, reload, icon refresh). Saves are
  debounced; a failed one retries every 3s while the window is open; an
  import's status line lasts until the next edit. Tests drive it by event
  sequences.
  A single `Window` scene, not `WindowGroup`: parallel config windows each held
  their own `@State` copy and clobbered each other's saves. App `init()` runs
  `QuickKeySync.sync()`.

## Spotlight surfacing rules (macOS 26, WWDC25 session 260 + live testing)

1. `parameterSummary` MUST contain every required no-default parameter, or
   the action silently disappears from Spotlight. Both `site` and `query`
   are in the Summary. Site is FIRST so text typed after a quick key filters
   the site dropdown.
2. `isDiscoverable` stays default-true; no `assistantOnly`.
3. `perform()` must exist.
4. Must be built with the macOS 26 SDK (Xcode 26) - older-toolchain binaries
   do not surface actions at all.
5. The .app should be in /Applications and launched once so Launch Services
   registers the App Intents metadata (`Metadata.appintents` in
   Contents/Resources - check it exists after build). `lsregister -f` if
   Spotlight misses a rebuild.
6. Only compile-time intent types are discoverable - nothing can be generated
   per site at runtime. 0.4.0-0.7.0 fought this with dedicated + slot intents;
   0.8.0 stopped fighting it (see Design direction).
7. A real (non-ad-hoc) signature is required at RUN time. See Signing.

## Quick-key store (undocumented)

Tahoe keeps action quick keys in the `com.apple.Spotlight` preference domain
under `SSActionKeyboardAliasStoreKey`:

    { "com.apple.shortcuts": { "<bundle-id>.<IntentTypeName>": "<abbrev>" } }

Spotlight observes the domain live - no restart, verified on 26.5. Since the
key is undocumented, `QuickKeySync.sync()` degrades to a no-op if the shape
ever changes rather than corrupting the store.

## Signing

`project.yml`: `CODE_SIGN_IDENTITY: "Apple Development"`, automatic style,
`DEVELOPMENT_TEAM: 7FDZK7U8A6` (the account that owns the Developer Program membership). Ad-hoc is NOT
viable - see Settled below.

Apple Development certs last one year, so this breaks annually. Symptoms:

    error: No signing certificate "Mac Development" found: No "Mac Development"
    signing certificate matching team ID "7FDZK7U8A6" with a private key

The stored Apple ID session tends to lapse alongside it, so
`-allowProvisioningUpdates` cannot self-heal (`Unable to log in with account
... The login details ... were rejected`). Recovery is GUI-only:

1. Xcode -> Settings -> Accounts, re-sign in to the team's Apple ID (2FA).
2. Select team "Zamua Nasrawt (7FDZK7U8A6)" -> Manage Certificates -> "+" ->
   Apple Development.
3. Verify: `security find-identity -v -p codesigning` shows 1 valid identity.

Already-signed builds keep running after expiry (the signature is embedded);
only new builds break. Renewed 2026-08-13; the prior cert expired 2026-06-25,
and expired certs accumulate in the login keychain - harmless, but delete the
stale one if a build ever complains about ambiguity.

## Build / dev loop

- `make build` - xcodegen (via nix) + xcodebuild Release into `.build/`.
  The .xcodeproj is generated; project.yml is the source of truth.
- `make test` - unit tests (URL building, defaults integrity, quick-key
  merge + legacy pruning, slot-config migration, entity filtering, search /
  bookmark split, site operations, locked mutation, MCP protocol + tools,
  share/import round-trip, window persistence, release config). The release
  config tests read the built bundle and the generated `project.pbxproj`
  (parsed as a plist, per target and config), never project.yml text.
  Note the test host IS the app binary, so a trap inside a test (a force
  unwrap of a stub's nil) kills the runner mid-suite and pops a macOS crash
  dialog. Use `XCTUnwrap`, never `!`, especially in red-phase tests.
- `make e2e` - `scripts/e2e-sites.sh` GETs every default template against the
  live site with a browser UA. Pass = HTTP < 400; 403/429/503 report as GATED
  (bot-blocked, not a failure - the URL still routes correctly). A unit test
  pins the script's list to `SiteStore.defaults` so they cannot drift.
- `make install` - ditto to /Applications + launch once.
- After an Xcode update, xcodebuild may die loading `IDESimulatorFoundation`
  ("A required plugin failed to load"). Fix: `xcodebuild -runFirstLaunch`.

## Settled - do not retry

- **Ad-hoc signing** (`CODE_SIGN_IDENTITY: "-"`) surfaces the intent in
  Spotlight, but the run-time XPC (Shortcuts -> app) is refused with
  "couldn't communicate with the app". Reproduced 3x on 26.5; a real Apple
  Development signature fixes it.
- **Parameterized App Shortcut phrases** do NOT surface as typeable Spotlight
  actions on 26.5. Removed in 0.8.0; only the plain phrase remains.
- **Accept-suggestion keystroke** in the Spotlight dropdown is Tab.
- **Spotlight DOES call `entities(matching:)`** for the inline parameter
  filter, so keyword matching works: verified 2026-08-13 on 26.5 with `ss`
  then `code`, which surfaces GitHub even though "code" appears nowhere in
  the title. Keywords are real filter text, not decoration.

## Design direction (0.8.0)

A fixed set of actions, one quick key each - `ss` -> Tab -> pick or type a
site keyword -> query, and `sb` -> pick a bookmark. What matters is that the
count is bounded by KINDS of thing, not by how many sites exist. The per-site
dedicated intents and the 20 `CustomSearchNIntent` slots are gone,
deliberately trading one-line search (`repo foo`) for:

- no ceiling on the number of sites (slots capped it at 20),
- real site names in the dropdown instead of "Custom Search 3",
- keywords that cannot collide with other apps' Spotlight abbreviations,
  because they are no longer registered as abbreviations at all,
- and the big one: a site added behind the app's back - by an agent writing
  `sites.json`, or an import - is searchable immediately. Slot allocation and
  quick-key writes only ever happened inside the GUI save path, so agent-added
  sites silently never got the one-line treatment.

The MCP server is the payoff: "add a site" is just an append to
`sites.json`. Favicons show in the dropdown via
`DisplayRepresentation(image:)` (`SiteEntity.swift`). Still to come: a
redesign of `.sitesearch` sharing. Storage
stays plain JSON: it is diffable, git-able, hand-editable, and the thing
feature #3 wants to share. See Concurrency.

## Concurrency

Two writers: the config window and the MCP server. The hazard is NOT torn
writes (`save` is atomic) but a lost update - a caller holding a stale list
writes all of it back and erases what the other one added. SQLite would not
fix this; a transaction makes the overwrite atomic, not correct.

1. DONE - writes express intent (`SiteOps`), never whole-array replacement.
2. DONE - `SiteStore.mutate` re-reads under an exclusive `flock` and persists,
   so a stale caller cannot clobber. The lock is a `sites.json.lock` sidecar:
   locking sites.json itself would race with the atomic replace in `save`,
   which swaps the inode out from under the holder. A lock that cannot be
   taken degrades to running unlocked rather than bricking the app.
3. DONE - `ConfigView` still holds the whole list in `@State` (SwiftUI's Table
   needs it) but never writes it back wholesale. `SiteReconcile.apply` is a
   three-way merge of (window's edits, baseline it last saw, fresh disk),
   applied inside `mutate`. Membership in baseline separates "the window added
   this" from "someone else deleted this"; per-field comparison over
   `SiteReconcile.fields` (a test checks it covers every editable `Site` field)
   separates "the window changed this" from "keep the external value".
   `SiteReconcile.persistable` is what a save writes: a row the window changed
   or added is written only once `SiteOps.problem` finds nothing wrong, while
   rows it did not touch are kept as they are (a hand-edited bad row is never
   erased). `SiteReconcile.absorb` is how the window reads disk, after a save
   or the 1.5s mtime poll: its unsaved edits stay shown and `baseline` becomes
   disk, so a held-back or not-yet-saved edit stays pending. Baselining the
   merged view instead marked such an edit as saved and lost it. `seenStamp`
   keeps our own saves from looking like someone else's. All of this state
   lives in `ConfigSync`.

## Known unknowns (prototype findings go here)

- Whether a newly added site appears in the dropdown without relaunching.
  `allEntities()` reads fresh from disk, but Spotlight's entity caching is
  unverified for additions.
- Windowless (LSUIElement) variant unverified for Spotlight surfacing;
  currently a normal windowed app.

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
  broke recents and pre-filled parameters). Explicit `CodingKeys` so a config
  written by 0.4.0-0.7.0 (carrying a per-site `slot`) still decodes and drops
  the dead field on rewrite.
- `Sources/SiteEntity.swift` - `SiteEntity: AppEntity` + `SiteEntityQuery`
  (`EnumerableEntityQuery` for the full dropdown, `EntityStringQuery` so the
  keyword alias matches during type-to-filter). Entity `id` is the Site's
  UUID string (stable across renames), keyword is the subtitle. `filter(_:
  matching:)` is the pure predicate behind `entities(matching:)` - name
  substring OR keyword prefix - extracted so it is unit-testable.
- `Sources/SearchSiteIntent.swift` - THE intent, and as of 0.8.0 the only one:
  two parameters (site entity + query). `supportedModes: .background`
  (macOS 26 API) so the app never foregrounds; `perform()` opens the URL via
  `NSWorkspace.shared.open`. Owns `buildURL`: RFC 3986 unreserved chars only
  (`.urlQueryAllowed` would pass `&`, `=`, `+` through), plus `{query}` and
  http(s)-scheme validation.

Config changes and agent access:

- `Sources/SiteOps.swift` - pure, intent-shaped operations (add one, update
  fields of one, remove one) plus `SiteOpError`. Never whole-list replacement:
  that is what let a stale snapshot clobber a concurrent write. Selectors
  accept an id or a keyword. Templates are validated with the same builder the
  search uses, so a site that stores cannot fail only at search time. Adding a
  duplicate keyword is an error here (an agent asked for `hn` and should be
  told), unlike import-merge which suffixes on purpose.
- `Sources/SiteURL.swift` - `SiteURL.build` + `SearchSiteError`, Foundation
  only, so the CLI can validate without importing AppIntents.
  `SearchSiteIntent.buildURL` forwards to it.
- `Sources/MCPHandler.swift` - the MCP server as a pure function of (request,
  config URL), with an injectable `opener` so `search_site` is testable without
  launching a browser. Shared by both targets so the unit tests can reach it.
  Tool failures come back as results with `isError`, not JSON-RPC errors: the
  call worked, the operation did not, and the agent needs to read why.
- `Sources/MCPMain/main.swift` - the stdio loop. EXCLUDED from the app target
  in project.yml (top-level code cannot coexist with the app's `@main`); built
  as the `sitesearch-mcp` tool target and copied into
  `Contents/MacOS/sitesearch-mcp` via a dependency `copy: destination:
  executables`. Note `embed: false` on that dependency silently suppresses the
  copy phase - do not add it back.

Quick keys:

- `Sources/QuickKeySync.swift` - registers exactly ONE quick key, `ss`, for
  the single action (see the undocumented key below). It does not vary with
  the config: site keywords are filter text inside the entity dropdown, not
  registered abbreviations, so adding a site writes nothing here. Entries
  belonging to other apps are never touched, an abbreviation another app's
  action already claims is never stolen, and any per-site entry left behind by
  0.4.0-0.7.0 is pruned by the same "our prefix becomes exactly desired" rule.

Sharing:

- `Sources/SiteExchange.swift` - the `.sitesearch` format (JSON v1, no ids -
  the receiver mints its own so imports never collide with the sender's entity
  identifiers). Merge skips entries whose (name, template) already exists and
  suffixes colliding keywords.
- `Sources/ShareSheets.swift` - export sheet (per-site checkboxes ->
  ShareLink / save panel) and import sheet (double-click a `.sitesearch` file,
  declared UTI `com.zamua.sitesearch.sites`).

UI:

- `Sources/ConfigView.swift` + `SiteSearchApp.swift` - plain SwiftUI window
  with an editable Table; debounced saves (was one disk write per keystroke).
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
`DEVELOPMENT_TEAM: 7FDZK7U8A6` (Apple ID the team's Apple ID). Ad-hoc is NOT
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
- `make test` - 57 unit tests (URL building, defaults integrity, quick-key
  merge + legacy pruning, slot-config migration, entity filtering, site
  operations, locked mutation, MCP protocol + tools, share/import round-trip).
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

One action, one quick key. `ss` -> Tab -> pick or type a site keyword ->
query. The per-site dedicated intents and the 20 `CustomSearchNIntent` slots
are gone, deliberately trading one-line search (`repo foo`) for:

- no ceiling on the number of sites (slots capped it at 20),
- real site names in the dropdown instead of "Custom Search 3",
- keywords that cannot collide with other apps' Spotlight abbreviations,
  because they are no longer registered as abbreviations at all,
- and the big one: a site added behind the app's back - by an agent writing
  `sites.json`, or an import - is searchable immediately. Slot allocation and
  quick-key writes only ever happened inside the GUI save path, so agent-added
  sites silently never got the one-line treatment.

The MCP server (0.9.0) is the payoff: "add a site" is now just an append to
`sites.json`. Still to come: favicons in the dropdown via
`DisplayRepresentation(image:)` - which has `init(data:)` and `init(url:)`,
verified in the 26.5 SDK - and a redesign of `.sitesearch` sharing. Storage
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
3. TODO - `ConfigView` still holds the whole list in `@State` and saves all of
   it on a 400ms debounce, so the window remains the one component that can
   clobber an agent's write. It needs a file watch plus per-field writes
   through `SiteOps`.

## Known unknowns (prototype findings go here)

- Whether a newly added site appears in the dropdown without relaunching.
  `allEntities()` reads fresh from disk, but Spotlight's entity caching is
  unverified for additions.
- Windowless (LSUIElement) variant unverified for Spotlight surfacing;
  currently a normal windowed app.

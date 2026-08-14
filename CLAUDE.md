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
- `make test` - 26 unit tests (URL building, defaults integrity, quick-key
  merge + legacy pruning, slot-config migration, entity filtering,
  share/import round-trip).
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

Next up: an MCP server so agents can manage sites (a stdio binary in the
bundle, sharing `Site.swift`), favicons in the dropdown via
`DisplayRepresentation(image:)`, and a redesign of `.sitesearch` sharing.
Storage stays plain JSON - see the concurrency note below.

## Concurrency (planned, not yet implemented)

Two writers are coming: the config window and the MCP server. The hazard is
NOT torn writes (`save` is already atomic) but a lost update - `ConfigView`
holds the whole list in `@State` and writes all of it back on a debounce, so
it would clobber a site added underneath it. SQLite does not fix this; a
transaction makes the overwrite atomic, not correct. The plan:

1. Writes express intent (add/update one site), never whole-array replacement.
2. `flock` around read-modify-write to serialize across processes.
3. A file watch in `ConfigView` so the window cannot hold a stale snapshot.

## Known unknowns (prototype findings go here)

- Whether a newly added site appears in the dropdown without relaunching.
  `allEntities()` reads fresh from disk, but Spotlight's entity caching is
  unverified for additions.
- Windowless (LSUIElement) variant unverified for Spotlight surfacing;
  currently a normal windowed app.

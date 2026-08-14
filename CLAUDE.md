# SiteSearch - working notes

Small macOS Tahoe app: user-configured keyword -> URL-template site search,
surfaced in Spotlight via App Intents. See README.md for the user-facing
story.

## Architecture

Model / storage:

- `Sources/Site.swift` - `Site` (id, keyword, name, template, slot) +
  `SiteStore`, a stateless enum that reads/writes
  `~/Library/Application Support/SiteSearch/sites.json` on every call.
  Stateless on purpose: the intent may run in a background-launched app
  instance, so reading fresh from disk avoids stale-config bugs. Defaults
  carry hardcoded UUIDs (Spotlight caches entity ids - fresh-per-launch ids
  broke recents and pre-filled parameters). `allocatingSlots` hands each
  custom site the lowest free slot 1...20; defaults never consume slots;
  `save()` re-syncs quick keys and returns the persisted array.
- `Sources/SiteEntity.swift` - `SiteEntity: AppEntity` + `SiteEntityQuery`
  (`EnumerableEntityQuery` for the full dropdown, `EntityStringQuery` so the
  keyword alias matches during type-to-filter). Entity `id` is the Site's
  UUID string (stable across renames), keyword is the subtitle.

Intents - three tiers, all compile-time types because Spotlight only
discovers intents from build-time metadata:

- `Sources/SearchSiteIntent.swift` - the generic two-parameter intent (site
  entity + query). `supportedModes: .background` (macOS 26 API) so the app
  never foregrounds; `perform()` opens the URL via `NSWorkspace.shared.open`.
  Owns `buildURL`, which every other intent reuses: RFC 3986 unreserved chars
  only (`.urlQueryAllowed` would pass `&`, `=`, `+` through), plus `{query}`
  and http(s)-scheme validation.
- `Sources/SiteIntents.swift` - one dedicated intent per built-in default
  (Google, GitHub, GitHub Repos) with a single query field, so each is its own
  Spotlight action and a quick key gives one-line search. Each resolves its
  template from the live config by site id (edits honored) and falls back to
  the built-in template if the site was deleted.
- `Sources/SlotIntents.swift` - 20 pre-compiled `CustomSearchNIntent` slots so
  runtime-added sites also get their own actions. The visible title is generic
  ("Custom Search 3") - Apple offers no way to rename an action at runtime -
  but the quick key and target site are the user's. Sites past slot 20 stay
  slotless and remain reachable via the generic Search Site.

Quick keys:

- `Sources/QuickKeySync.swift` - mirrors the config into Spotlight's quick-key
  store (see the undocumented key below). A site's KEYWORD *is* its quick key:
  one source of truth, edited in the config window. Desired map = generic
  action (`ws`) + dedicated defaults + slotted customs. Our entries add /
  update / prune on every launch and save; entries belonging to other apps are
  never touched; an abbreviation another app's action already claims is never
  stolen.

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
6. Only compile-time intent types are discoverable - hence the dedicated and
   slot intents rather than anything generated per site at runtime.
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
- `make test` - 29 unit tests (URL building, defaults integrity, quick-key
  merge, slot allocation, share/import round-trip).
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
  actions on 26.5. The experiment stays in the code only for Shortcuts-app
  niceness.
- **Accept-suggestion keystroke** in the Spotlight dropdown is Tab.

## Known unknowns (prototype findings go here)

- Windowless (LSUIElement) variant unverified for Spotlight surfacing;
  currently a normal windowed app.
- Whether Spotlight's type-to-filter matches the entity subtitle (keyword)
  or only the title; EntityStringQuery covers keyword matching if invoked.
- No known way to give a slot intent a per-site title in the Spotlight list;
  users see "Custom Search N" next to their own quick key.

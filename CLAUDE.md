# SiteSearch - working notes

Small macOS Tahoe app: user-configured keyword -> URL-template site search,
surfaced in Spotlight via App Intents. See README.md for the user-facing
story.

## Architecture

- `Sources/Site.swift` - `Site` model + `SiteStore`, a stateless enum that
  reads/writes `~/Library/Application Support/SiteSearch/sites.json` on every
  call. Stateless on purpose: the intent may run in a background-launched
  app instance, so reading fresh from disk avoids stale-config bugs.
- `Sources/SiteEntity.swift` - `SiteEntity: AppEntity` + `SiteEntityQuery`
  (`EnumerableEntityQuery` for the full dropdown, `EntityStringQuery` so the
  keyword alias matches during type-to-filter). Entity `id` is the Site's
  UUID string (stable across renames), keyword is the subtitle.
- `Sources/SearchSiteIntent.swift` - the intent. `supportedModes: .background`
  (macOS 26 API) so the app never foregrounds; `perform()` builds the URL and
  opens it via `NSWorkspace.shared.open`. Query encoding uses RFC 3986
  unreserved chars only (`.urlQueryAllowed` would pass `&`, `=`, `+` through).
- `Sources/ConfigView.swift` + `SiteSearchApp.swift` - plain SwiftUI window
  with an editable Table; saves on every change.

## Spotlight surfacing rules (macOS 26, from WWDC25 session 260)

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

## Build / dev loop

- `make build` - xcodegen (via nix) + xcodebuild Release into `.build/`.
  The .xcodeproj is generated; project.yml is the source of truth.
- `make install` - ditto to /Applications + launch once.
- Ad-hoc signed (`CODE_SIGN_IDENTITY: "-"`). Unverified whether Spotlight
  requires more than ad-hoc; if actions never appear, try Apple-Development
  signing before debugging anything else.

## Known unknowns (prototype findings go here)

- Windowless (LSUIElement) variant unverified for Spotlight surfacing;
  currently a normal windowed app.
- Whether Spotlight's type-to-filter matches the entity subtitle (keyword)
  or only the title; EntityStringQuery covers keyword matching if invoked.
- Exact accept-suggestion keystroke in the Spotlight dropdown.

# SiteSearch

Custom website search for macOS Tahoe Spotlight. Configure keyword-to-URL
mappings in a small window, then search any of them straight from Spotlight:
Cmd-Space, type the action's quick key, pick a site, type your query, Return.
Your default browser opens the site's search results. A native replacement
for the web-search half of Alfred/Raycast.

Requires macOS 26 (Tahoe). Running App Intents actions from Spotlight is a
Mac-only macOS 26 feature.

## How it works

The app exposes a single App Intent, "Search Site", with two parameters:

- **Site**: an `AppEntity` backed by your configured site list. Spotlight
  renders it as a dropdown and filters it as you type.
- **Query**: free text, percent-encoded into the site's URL template.

Sites live in `~/Library/Application Support/SiteSearch/sites.json` as plain
JSON (version-control it if you like). The URL template uses the literal
placeholder `{query}`, e.g. `https://github.com/search?q={query}`.

## Build

Requires Xcode 26 (the macOS 26 SDK) and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(the Makefile fetches it via nix).

```sh
make install   # generate project, build Release, copy to /Applications, launch
```

## First-time Spotlight setup

1. Launch the app once (registers it with Launch Services).
2. Cmd-Space, press Cmd-3 (Actions), find "Search Site".
3. Click "Add quick keys" next to it and pick something short, e.g. `ws`.
4. Use it: Cmd-Space, `ws git`, Tab, your query, Return.

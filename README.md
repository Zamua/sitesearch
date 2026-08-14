# SiteSearch

Custom website search for macOS Tahoe Spotlight. Configure keyword-to-URL
mappings in a small window, then search any of them straight from Spotlight:
Cmd-Space, `ss`, pick a site (or type its keyword), Tab, your query, Return.
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

1. Launch the app once. That registers it with Launch Services and asks
   Spotlight for the quick key `ss`.
2. Use it: Cmd-Space, `ss git`, Tab, your query, Return.

If `ss` does nothing, assign it by hand once: Cmd-Space, Cmd-3 (Actions),
find "Search Site", "Add quick keys", type `ss`. (Another app may already
own the abbreviation, in which case pick a different one - the app never
takes an abbreviation something else has claimed.)

Adding sites needs no setup at all. There is one action and one quick key;
a site you add - in the window, by importing a `.sitesearch` file, or by
editing `sites.json` directly - is searchable immediately, no relaunch.

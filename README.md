# SiteSearch

Custom website search for macOS Tahoe Spotlight. Configure keyword-to-URL
mappings in a small window, then search any of them straight from Spotlight:
Cmd-Space, `ss`, pick a site (or type its keyword), Tab, your query, Return.
Your default browser opens the site's search results. A native replacement
for the web-search half of Alfred/Raycast.

Requires macOS 26 (Tahoe). Running App Intents actions from Spotlight is a
Mac-only macOS 26 feature.

## Install

```sh
brew install --cask zamua/tap/sitesearch
```

Or grab the notarized zip from [Releases](https://github.com/Zamua/sitesearch/releases)
and drag it to /Applications.

## How it works

The app exposes a single App Intent, "Search Site", with two parameters:

- **Site**: an `AppEntity` backed by your configured site list. Spotlight
  renders it as a dropdown and filters it as you type.
- **Query**: free text, percent-encoded into the site's URL template.

Sites live in `~/Library/Application Support/SiteSearch/sites.json` as plain
JSON (version-control it if you like). The URL template uses the literal
placeholder `{query}`, e.g. `https://github.com/search?q={query}`.

Leave `{query}` out and the entry becomes a **bookmark**: `ss repo1` opens it
directly, no query step. Searches and bookmarks share one list and one set of
keywords, so `ss repo` shows your `repo` search next to `repo1` and `repo2`.

Each site's favicon is fetched from that site's own origin when you add it -
never through a third-party favicon service - and cached alongside the config
in `icons/`. Sites without a reachable icon fall back to a plain glyph.

## Agent access (MCP)

The bundle ships a stdio MCP server so an agent can manage sites without the
GUI. Point any MCP client at it:

```json
{
  "mcpServers": {
    "sitesearch": {
      "command": "/Applications/SiteSearch.app/Contents/MacOS/sitesearch-mcp"
    }
  }
}
```

Claude Code:

```sh
claude mcp add sitesearch /Applications/SiteSearch.app/Contents/MacOS/sitesearch-mcp
```

Tools: `list_sites`, `add_site`, `update_site`, `remove_site`, and
`search_site` (which opens the search in your browser). A site added this way
is searchable in Spotlight immediately - no relaunch, no setup step. Writes
are serialized with a file lock, so the agent and the config window can both
be open without either clobbering the other.

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

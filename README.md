# SiteSearch

Custom website search for Spotlight. `⌘Space`, `ss`, pick a site, `Tab`, your
query, and your browser opens that site's results. Requires macOS 26 (Tahoe).

```sh
brew install --cask zamua/tap/sitesearch
```

Or drag the notarized zip from [Releases](https://github.com/Zamua/sitesearch/releases)
to /Applications. Launch once, then it's ready.

## Sites

Add them in the app window, by importing a `.sitesearch` file, or by editing
`~/Library/Application Support/SiteSearch/sites.json`. Any of the three is
live immediately, no relaunch. The file is an array of entries like this; an
`id` is added for you:

```json
{ "name": "GitHub", "keyword": "gh",
  "template": "https://github.com/search?q={query}" }
```

Drop the `{query}` and it's a **bookmark** instead: `sb` opens it directly.
Favicons are fetched from each site's own origin, never a third-party service.

## Agent access (MCP)

The bundle ships a stdio MCP server:

```sh
claude mcp add sitesearch /Applications/SiteSearch.app/Contents/MacOS/sitesearch-mcp
```

Tools: `list_sites`, `add_site`, `update_site`, `remove_site`, `search_site`.
Writes are file-locked, so the agent and the window can't clobber each other.

## Build

Needs Xcode 26; the Makefile fetches XcodeGen via nix.

```sh
make install
```

## If `ss` does nothing

Assign it by hand once: `⌘Space`, `⌘3` (Actions), find "Search Site" →
"Add quick keys" → `ss`. Another app may already own the abbreviation;
SiteSearch never takes one that's claimed.

MIT

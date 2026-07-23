#!/bin/bash
# E2E check of every default site's search-URL pattern against the live site.
#
# For each site, builds the URL exactly as SearchSiteIntent does (replace
# {query} with a percent-encoded probe) and GETs it. Pass = HTTP < 400.
# Bot-gated responses (403/429/503) are reported as GATED, not failures:
# they prove the URL routes to the search endpoint but the site blocks
# non-browser clients; verify those by eye in a real browser once.
#
# Usage: scripts/e2e-sites.sh [query]   (default probe: "hello world")

set -u
QUERY="${1:-hello world}"
ENCODED=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$QUERY")
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

# name|template  - keep in sync with SiteStore.defaults in Sources/Site.swift
SITES="
Google|https://www.google.com/search?q={query}
GitHub|https://github.com/search?q={query}
GitHub Repos|https://github.com/search?q={query}&type=repositories
"

pass=0; gated=0; fail=0
while IFS='|' read -r name template; do
  [ -z "$name" ] && continue
  url="${template//\{query\}/$ENCODED}"
  code=$(curl -sS -o /dev/null -w "%{http_code}" -L --max-time 20 -A "$UA" "$url" 2>/dev/null)
  case "$code" in
    2*|3*) echo "PASS   $code  $name"; pass=$((pass+1)) ;;
    403|429|503) echo "GATED  $code  $name  (bot-blocked; verify in browser)"; gated=$((gated+1)) ;;
    *) echo "FAIL   $code  $name  $url"; fail=$((fail+1)) ;;
  esac
done <<< "$SITES"

echo "----"
echo "pass=$pass gated=$gated fail=$fail"
[ "$fail" -eq 0 ]

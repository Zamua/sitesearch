# Canonical source for the Homebrew cask. Copy to Casks/sitesearch.rb in
# Zamua/homebrew-tap on each release, updating version + sha256 (the release
# workflow prints both in its job summary).
#
#   brew install --cask zamua/tap/sitesearch
cask "sitesearch" do
  version "0.10.0"
  sha256 "REPLACE_WITH_RELEASE_SHA256"

  url "https://github.com/Zamua/sitesearch/releases/download/v#{version}/SiteSearch-#{version}.zip"
  name "SiteSearch"
  desc "Custom website search for macOS Spotlight"
  homepage "https://github.com/Zamua/sitesearch"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Running App Intents actions from Spotlight is macOS 26 and later only.
  depends_on macos: ">= :tahoe"

  app "SiteSearch.app"

  caveats do
    <<~EOS
      Launch SiteSearch once so Launch Services registers its Spotlight action,
      then search with:

          Cmd-Space, "ss", Tab, pick a site, type your query

      An MCP server for agents ships inside the app:

          claude mcp add sitesearch #{appdir}/SiteSearch.app/Contents/MacOS/sitesearch-mcp
    EOS
  end

  zap trash: [
    "~/Library/Application Support/SiteSearch",
  ]
end

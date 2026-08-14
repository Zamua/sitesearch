#!/bin/bash
# Wires up the five GitHub secrets the release workflow needs.
#
# Prerequisites:
#   1. A paid Apple Developer Program membership.
#   2. A "Developer ID Application" certificate in your login keychain:
#      Xcode -> Settings -> Accounts -> Manage Certificates -> "+" ->
#      Developer ID Application.
#   3. An app-specific password from appleid.apple.com (Sign-In and Security ->
#      App-Specific Passwords). NOT your Apple ID password.
#
# Usage: scripts/setup-release-secrets.sh [owner/repo]

set -euo pipefail

REPO="${1:-Zamua/sitesearch}"

echo "==> Looking for a Developer ID Application certificate"
IDENTITY=$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" \
  | head -1 \
  | sed -E 's/.*"(.*)"/\1/') || true

if [ -z "${IDENTITY:-}" ]; then
  cat <<'EOF'
No "Developer ID Application" identity found in your keychain.

If you just enrolled, check that the membership is active:
  Xcode -> Settings -> Accounts -> Manage Certificates -> "+"
"Developer ID Application" only appears once enrollment completes.

Create it there, then re-run this script.
EOF
  exit 1
fi

echo "    found: $IDENTITY"
# "Developer ID Application: Some Name (TEAMID)" -> TEAMID
TEAM_ID=$(printf '%s' "$IDENTITY" | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/')
echo "    team:  $TEAM_ID"

echo
echo "==> Exporting the identity"
echo "    Keychain Access may prompt for permission to export the private key."
P12=$(mktemp -t sitesearch-cert).p12
P12_PASSWORD=$(uuidgen)

if ! security export -t identities -f pkcs12 -P "$P12_PASSWORD" -o "$P12" 2>/dev/null; then
  cat <<EOF

Automatic export failed (this is common - the private key may be marked
non-exportable without an interactive prompt).

Export manually instead:
  1. Open Keychain Access
  2. Find "$IDENTITY"
  3. Right-click -> Export -> save as cert.p12, set a password
  4. Then run:

     base64 -i cert.p12 | gh secret set DEVELOPER_ID_P12 --repo $REPO
     gh secret set DEVELOPER_ID_P12_PASSWORD --repo $REPO
     gh secret set APPLE_TEAM_ID --body "$TEAM_ID" --repo $REPO
     gh secret set APPLE_ID --repo $REPO
     gh secret set APPLE_APP_PASSWORD --repo $REPO

EOF
  exit 1
fi

echo
read -r -p "Apple ID email that owns the membership: " APPLE_ID
read -r -s -p "App-specific password (from appleid.apple.com): " APPLE_APP_PASSWORD
echo

echo
echo "==> Setting secrets on $REPO"
base64 -i "$P12" | gh secret set DEVELOPER_ID_P12 --repo "$REPO"
gh secret set DEVELOPER_ID_P12_PASSWORD --body "$P12_PASSWORD" --repo "$REPO"
gh secret set APPLE_TEAM_ID --body "$TEAM_ID" --repo "$REPO"
gh secret set APPLE_ID --body "$APPLE_ID" --repo "$REPO"
gh secret set APPLE_APP_PASSWORD --body "$APPLE_APP_PASSWORD" --repo "$REPO"

rm -f "$P12"

echo
echo "Done. Ship a release with:"
echo "    git tag v\$(grep MARKETING_VERSION project.yml | sed -E 's/.*\"(.*)\".*/\\1/')"
echo "    git push origin --tags"

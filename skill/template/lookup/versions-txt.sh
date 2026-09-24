# --- release lookup: versions.txt on the versions branch ---------------------
# new-package.sh inserts this for a package in a monorepo. There,
# /releases/latest returns whichever package released last, so the repo's
# release workflow keeps one line per package — "<name> <version>" — in
# versions.txt on the versions branch. It writes a package's line only after
# that release's tarball is uploaded, and never for a pre-release, so the file
# never names a version that cannot be downloaded.
#
# release_lookup sets tag, latest and rel_url, or returns 1 with the reason in
# lookup_error. It runs curl as "${CURL[@]}", so a caller can wrap it in
# `timeout`. VERSIONS_URL can be overridden, which is how tests run it against
# a local file.

VERSIONS_URL="${VERSIONS_URL:-https://raw.githubusercontent.com/$GITHUB_SLUG/versions/versions.txt}"

release_lookup() {
  local list
  tag=""; latest=""; rel_url=""; lookup_error=""

  list=$("${CURL[@]}" -fsSL "$VERSIONS_URL" 2>/dev/null) \
    || { lookup_error="Could not read $VERSIONS_URL — no release published yet, or no network."; return 1; }

  latest=$(printf '%s\n' "$list" | awk -v p="$PROJECT" '$1 == p { print $2; exit }' \
    | grep -E '^[0-9]+(\.[0-9]+)*$') || true
  [ -n "$latest" ] || { lookup_error="$VERSIONS_URL lists no release of $PROJECT yet."; return 1; }

  tag="$PROJECT-v$latest"
  rel_url="https://github.com/$GITHUB_SLUG/releases/tag/$tag"
}

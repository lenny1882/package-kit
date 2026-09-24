# --- release lookup: GitHub's /releases/latest -------------------------------
# new-package.sh inserts this for a package that has a repo to itself. The
# newest release in the repo is then this package's newest, and the endpoint
# skips a release left as a draft or marked pre-release no matter how its
# version number sorts.
#
# release_lookup sets tag, latest and rel_url, or returns 1 with the reason in
# lookup_error. It runs curl as "${CURL[@]}", so a caller can wrap it in
# `timeout`. `jq` is used when present; otherwise a plain-text scrape of the
# API response takes over.

# Pull one string field out of a JSON blob: $1 is the JSON, $2 the field name.
# The scrape is good enough for the flat string fields read here.
json_field() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r --arg f "$2" '.[$f] // empty'
  else
    printf '%s' "$1" \
      | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 \
      | sed -E 's/.*:[[:space:]]*"(.*)"$/\1/'
  fi
}

release_lookup() {
  local response http_code json
  tag=""; latest=""; rel_url=""; lookup_error=""

  response=$("${CURL[@]}" -sSL -w '\n%{http_code}' -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$GITHUB_SLUG/releases/latest" 2>/dev/null) \
    || { lookup_error="Could not reach the GitHub Releases API. Check the network."; return 1; }
  http_code=$(printf '%s' "$response" | tail -1)
  json=$(printf '%s' "$response" | sed '$d')

  case "$http_code" in
    200) ;;
    404) lookup_error="GitHub reports no releases yet for $GITHUB_SLUG."; return 1 ;;
    *)   lookup_error="GitHub Releases API returned HTTP $http_code for $GITHUB_SLUG."; return 1 ;;
  esac

  tag=$(json_field "$json" tag_name)
  latest=$(printf '%s' "$tag" | sed 's/^v//' | grep -E '^[0-9]+(\.[0-9]+)*$') || true
  [ -n "$latest" ] || { lookup_error="GitHub reports no releases yet for $GITHUB_SLUG."; return 1; }
  rel_url=$(json_field "$json" html_url)
}

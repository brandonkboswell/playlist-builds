#!/usr/bin/env bash
#
# Re-point the Short.io download links at a GitHub release's assets.
#
# Env:
#   SHORTIO_API_KEY  (required) Short.io secret key, from Integrations & API
#   TAG              (required) release tag, e.g. 0.67.0
#   GH_TOKEN         (required) for `gh api`
#   DRY_RUN          "true" to log the intended changes without writing
#
set -euo pipefail

DOMAIN="link.brandonkboswell.com"

# Short.io slug  ->  suffix of the release asset it should point at.
# Matching by suffix rather than by full filename keeps this working if the tag
# ever drifts from the version baked into the asset name (e.g. a `v` prefix).
LINKS=(
  "playlist-mac.dmg:-arm64.dmg"
  "playlist-mac-apple-silicon.dmg:-arm64.dmg"
  "playlist-mac-intel.dmg:-x64.dmg"
)

: "${SHORTIO_API_KEY:?SHORTIO_API_KEY is not set}"
: "${TAG:?TAG is not set}"
DRY_RUN="${DRY_RUN:-false}"

log()  { printf '%s\n' "$*"; }
fail() { printf '::error::%s\n' "$*" >&2; exit 1; }

summary() {
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && printf '%s\n' "$*" >>"$GITHUB_STEP_SUMMARY"
  return 0
}

# --- resolve the release -----------------------------------------------------

log "Reading release $TAG from ${GITHUB_REPOSITORY:-<unknown repo>}"
release="$(gh api "repos/${GITHUB_REPOSITORY}/releases/tags/${TAG}")" \
  || fail "No release found for tag '$TAG'"

# Returns the browser_download_url of the single asset ending in $1.
asset_url() {
  local suffix="$1" urls count
  urls="$(jq -r --arg s "$suffix" \
    '[.assets[] | select(.name | endswith($s)) | .browser_download_url] | .[]' \
    <<<"$release")"
  count="$(jq -r --arg s "$suffix" \
    '[.assets[] | select(.name | endswith($s))] | length' <<<"$release")"

  case "$count" in
    0) fail "Release $TAG has no asset ending in '$suffix'. Attach the installers before publishing, then re-run this workflow manually." ;;
    1) printf '%s' "$urls" ;;
    *) fail "Release $TAG has $count assets ending in '$suffix'; expected exactly one." ;;
  esac
}

# --- Short.io ----------------------------------------------------------------

# expand <slug> -> the link object as JSON
expand() {
  local slug="$1" out status body
  out="$(curl -sS -w $'\n%{http_code}' --get "https://api.short.io/links/expand" \
    --data-urlencode "domain=${DOMAIN}" \
    --data-urlencode "path=${slug}" \
    -H "Authorization: ${SHORTIO_API_KEY}" \
    -H 'accept: application/json')"
  status="${out##*$'\n'}"
  body="${out%$'\n'*}"
  [[ "$status" == 200 ]] || fail "Lookup of ${DOMAIN}/${slug} failed (HTTP $status): $body"
  printf '%s' "$body"
}

# set_url <link-id> <url>
set_url() {
  local id="$1" url="$2" out status body
  out="$(curl -sS -w $'\n%{http_code}' -X POST "https://api.short.io/links/${id}" \
    -H "Authorization: ${SHORTIO_API_KEY}" \
    -H 'accept: application/json' \
    -H 'content-type: application/json' \
    --data "$(jq -nc --arg u "$url" '{originalURL: $u}')")"
  status="${out##*$'\n'}"
  body="${out%$'\n'*}"
  [[ "$status" == 200 ]] || fail "Update of link ${id} failed (HTTP $status): $body"
}

# --- do the work -------------------------------------------------------------

summary "## Short.io download links — \`$TAG\`"
summary ""
if [[ "$DRY_RUN" == "true" ]]; then
  summary "_Dry run — nothing was written._"
  summary ""
fi
summary "| Slug | Status | Target |"
summary "| --- | --- | --- |"

for entry in "${LINKS[@]}"; do
  slug="${entry%%:*}"
  suffix="${entry#*:}"

  target="$(asset_url "$suffix")"
  link="$(expand "$slug")"
  id="$(jq -r '.idString // .id' <<<"$link")"
  current="$(jq -r '.originalURL' <<<"$link")"

  [[ -n "$id" && "$id" != "null" ]] || fail "Could not read a link ID for ${DOMAIN}/${slug}"

  if [[ "$current" == "$target" ]]; then
    log "= ${slug} already points at ${target}"
    summary "| \`${slug}\` | unchanged | ${target##*/} |"
    continue
  fi

  log "→ ${slug}"
  log "    from ${current}"
  log "      to ${target}"

  if [[ "$DRY_RUN" == "true" ]]; then
    summary "| \`${slug}\` | would update | ${target##*/} |"
    continue
  fi

  set_url "$id" "$target"

  # Read it back — a 200 alone is not proof the value stuck.
  verified="$(jq -r '.originalURL' <<<"$(expand "$slug")")"
  [[ "$verified" == "$target" ]] \
    || fail "${slug} still points at ${verified} after the update"

  log "    updated"
  summary "| \`${slug}\` | updated | ${target##*/} |"
done

log "Done."

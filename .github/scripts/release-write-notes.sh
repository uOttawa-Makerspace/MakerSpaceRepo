#!/usr/bin/env bash
# Writes CHANGELOG.md (shown on /changelog) and release-notes.md (the GitHub Release body).
#
# Env: GH_TOKEN, GITHUB_REPOSITORY
#      NOTES      notes built for this release (may be empty)
#      VERSION    the release's version on master, empty on staging
#      TARGET_REF refs/heads/master or refs/heads/staging
#      NOTES_ONLY true: write release-notes.md only (no releases fetch, no CHANGELOG.md)
# The notes come from PR titles, so they reach this script through the environment only.
set -euo pipefail

has_notes=false
if printf '%s' "$NOTES" | grep -q '[^[:space:]]'; then
  has_notes=true
fi

if [ "$has_notes" = true ]; then
  printf '%s\n' "$NOTES" > release-notes.md
else
  printf 'No notable changes.\n' > release-notes.md
fi

if [ "${NOTES_ONLY:-false}" = true ]; then
  exit 0
fi

releases=$(gh api "repos/$GITHUB_REPOSITORY/releases?per_page=10")
{
  if [ "$has_notes" = true ]; then
    if [ "$TARGET_REF" = "refs/heads/master" ]; then
      published=$(jq -r --arg v "$VERSION" '[.[] | select(.tag_name == $v and (.draft | not))][0].published_at[0:10] // ""' <<< "$releases")
      printf '# %s (%s)\n\n%s\n\n' "$VERSION" "${published:-$(date -u +%Y-%m-%d)}" "$NOTES"
    else
      printf '# Unreleased (on staging)\n\n%s\n\n' "$NOTES"
    fi
    # the section above replaces this release's entry
    jq -r --arg v "$VERSION" \
      '.[] | select((.draft | not) and .tag_name != $v) | "# \(.tag_name) (\(.published_at[0:10]))\n\n\(.body)\n"' <<< "$releases"
  else
    # Notes were not rebuilt: an already published release for this version stays the first
    # section, taken from its own body.
    jq -r '.[] | select(.draft | not) | "# \(.tag_name) (\(.published_at[0:10]))\n\n\(.body)\n"' <<< "$releases"
  fi
} > CHANGELOG.md

if ! grep -q '[^[:space:]]' CHANGELOG.md; then
  printf '# Changelog\n\nNo releases yet.\n' > CHANGELOG.md
fi

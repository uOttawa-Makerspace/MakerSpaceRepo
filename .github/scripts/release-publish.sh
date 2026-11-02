#!/usr/bin/env bash
# Tags the shipped commit and publishes the GitHub Release. Existing tags and releases are kept.
# Env: GH_TOKEN, GITHUB_REPOSITORY, VERSION, SHIPPED; release-notes.md in the working directory.
set -euo pipefail

if ! gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$VERSION" --silent; then
  gh api "repos/$GITHUB_REPOSITORY/git/refs" -f ref="refs/tags/$VERSION" -f sha="$SHIPPED" --silent
fi
if ! gh release view "$VERSION" --repo "$GITHUB_REPOSITORY" --json tagName --jq .tagName; then
  gh release create "$VERSION" --repo "$GITHUB_REPOSITORY" --verify-tag \
    --title "$VERSION" --notes-file release-notes.md
fi

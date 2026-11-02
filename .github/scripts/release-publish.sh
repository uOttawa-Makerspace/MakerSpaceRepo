#!/usr/bin/env bash
# Tags the shipped commit and publishes the GitHub Release. An existing tag or release for the
# version is kept, but a tag on a different commit is an error.
# Env: GH_TOKEN, GITHUB_REPOSITORY, RUNNER_TEMP, VERSION, SHIPPED; release-notes.md in the
# working directory.
set -euo pipefail

err_file="$RUNNER_TEMP/gh-error.txt"

# Prints the commit the tag $VERSION points at (annotated tags peeled), or nothing when the tag
# does not exist. Any other error fails.
tag_commit() {
  local info type sha
  if info=$(gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$VERSION" --jq '"\(.object.type) \(.object.sha)"' 2> "$err_file"); then
    read -r type sha <<< "$info"
    if [ "$type" = "tag" ]; then
      sha=$(gh api "repos/$GITHUB_REPOSITORY/git/tags/$sha" --jq '.object.sha')
    fi
    echo "$sha"
  elif grep -q 'HTTP 404' "$err_file"; then
    echo ""
  else
    cat "$err_file" >&2
    return 1
  fi
}

current=$(tag_commit)
if [ -z "$current" ]; then
  if ! gh api "repos/$GITHUB_REPOSITORY/git/refs" -f ref="refs/tags/$VERSION" -f sha="$SHIPPED" --silent 2> "$err_file"; then
    if grep -q 'HTTP 422' "$err_file"; then
      # created by a concurrent run meanwhile: accept it only if it is on the shipped commit
      current=$(tag_commit)
    else
      cat "$err_file" >&2
      exit 1
    fi
  else
    current="$SHIPPED"
  fi
fi
if [ "$current" != "$SHIPPED" ]; then
  echo "::error::Tag $VERSION already exists but does not point at the shipped commit $SHIPPED; nothing was published."
  exit 1
fi

if ! gh release view "$VERSION" --repo "$GITHUB_REPOSITORY" --json tagName --jq .tagName; then
  gh release create "$VERSION" --repo "$GITHUB_REPOSITORY" --verify-tag \
    --title "$VERSION" --notes-file release-notes.md
fi

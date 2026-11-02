#!/usr/bin/env bash
# Works out what a push ships and which release precedes it. Writes shipped, publishable,
# version and previous to $GITHUB_OUTPUT.
#
# Env: GH_TOKEN, GITHUB_REPOSITORY, GITHUB_OUTPUT, RUNNER_TEMP
#      TARGET_REF  refs/heads/master or refs/heads/staging
#      TARGET_SHA  the pushed commit (on master: the release's squash commit)
#
# Releases are squash-merged from staging, so on master the shipped commit is the head of the
# staging -> master PR whose merge commit is TARGET_SHA. If no such PR is found the release is
# marked unpublishable; the master sha is never used in its place.
set -euo pipefail

repo="$GITHUB_REPOSITORY"
shipped="$TARGET_SHA"
publishable=true
version=""

# prints the head sha of the release PR for $TARGET_SHA among the PRs on stdin (a JSON array)
pick_head() {
  jq -r --arg sha "$TARGET_SHA" --arg repo "$repo" \
    '[.[] | select(.merge_commit_sha == $sha and .merged_at != null and .base.ref == "master"
                   and .head.ref == "staging" and .head.repo.full_name == $repo)][0].head.sha // ""'
}

if [ "$TARGET_REF" = "refs/heads/master" ]; then
  shipped=""
  # The PRs associated with the commit; the API can lag behind the push, so retry briefly.
  err_file="$RUNNER_TEMP/gh-error.txt"
  for attempt in 1 2 3 4 5; do
    if prs=$(gh api "repos/$repo/commits/$TARGET_SHA/pulls" 2> "$err_file"); then
      shipped=$(pick_head <<< "$prs")
    elif grep -qE 'HTTP 4[0-9][0-9]' "$err_file"; then
      # an unknown commit or a permission problem will not fix itself
      cat "$err_file" >&2
      echo "::error::Could not list the pull requests of $TARGET_SHA."
      exit 1
    else
      echo "::warning::Could not list the pull requests of $TARGET_SHA (attempt $attempt of 5)"
    fi
    if [ -n "$shipped" ]; then
      break
    fi
    if [ "$attempt" -lt 5 ]; then
      sleep 10
    fi
  done
  # Fall back to the newest closed PRs into master (3 pages of 50).
  if [ -z "$shipped" ]; then
    for page in 1 2 3; do
      if prs=$(gh api "repos/$repo/pulls?state=closed&base=master&sort=updated&direction=desc&per_page=50&page=$page"); then
        shipped=$(pick_head <<< "$prs")
      else
        echo "::warning::Could not list closed pull requests (page $page)"
      fi
      if [ -n "$shipped" ]; then
        break
      fi
    done
  fi
  if [ -z "$shipped" ]; then
    publishable=false
    echo "::warning::No merged staging -> master pull request has merge commit $TARGET_SHA; this commit cannot be published as a release."
  fi
fi

# Tags as "<commit sha> refs/tags/<name>", annotated tags peeled to the commit they point at.
tags_file="$RUNNER_TEMP/release-tags.txt"
releases_file="$RUNNER_TEMP/release-names.txt"
git ls-remote --tags origin 'refs/tags/v*' | awk '
  { name = $2; if (name ~ /\^\{\}$/) { sub(/\^\{\}$/, "", name); peeled[name] = $1 } else { direct[name] = $1 } }
  END { for (n in direct) print (n in peeled ? peeled[n] : direct[n]), n }
' > "$tags_file"
gh release list --repo "$repo" --limit 30 --exclude-drafts --json tagName --jq '.[].tagName' > "$releases_file"

if [ "$publishable" = true ] && [ "$TARGET_REF" = "refs/heads/master" ]; then
  # A tag already on the shipped commit is this release (a re-run); otherwise derive the version
  # from the commit: its committer date in UTC plus its short sha.
  version=$(awk -v s="$shipped" '$1 == s { sub("^refs/tags/", "", $2); print $2; exit }' "$tags_file")
  if [ -z "$version" ]; then
    committed=$(gh api "repos/$repo/commits/$shipped" --jq '.commit.committer.date')
    version="v$(date -u -d "$committed" +'%Y.%m.%d-%H%M%S')-${shipped:0:7}"
  fi
fi

# The newest release (by creation) whose tag is not on the shipped commit.
previous=$(awk -v s="$shipped" '
  FILENAME == ARGV[1] { if ($1 != s) { t = $2; sub("^refs/tags/", "", t); ok[t] = 1 } ; next }
  $1 in ok { print $1; exit }
' "$tags_file" "$releases_file")

{
  echo "shipped=$shipped"
  echo "publishable=$publishable"
  echo "version=$version"
  echo "previous=$previous"
} >> "$GITHUB_OUTPUT"

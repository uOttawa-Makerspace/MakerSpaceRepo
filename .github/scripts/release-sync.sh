#!/usr/bin/env bash
# Opens (or reuses) the master -> staging sync PR, labelled release so the notes ignore it, and
# turns on auto-merge. Does nothing when staging already contains master.
# Env: GH_TOKEN, GITHUB_REPOSITORY
set -euo pipefail

ahead=$(gh api "repos/$GITHUB_REPOSITORY/compare/staging...master" --jq '.ahead_by')
if [ "$ahead" = "0" ]; then
  echo "staging already contains master; nothing to sync."
  exit 0
fi

# only created when missing, so a maintainer's colour and description survive
if ! gh label view release --repo "$GITHUB_REPOSITORY" --json name --jq .name; then
  gh label create release --repo "$GITHUB_REPOSITORY" --color 0E8A16 \
    --description "Release and sync pull requests"
fi

existing=$(gh pr list --repo "$GITHUB_REPOSITORY" --base staging --head master --state open --json number --jq '.[0].number // ""')
if [ -z "$existing" ]; then
  gh pr create --repo "$GITHUB_REPOSITORY" --base staging --head master \
    --title "Sync master into staging" \
    --body "Brings the release squash commit into staging's history, so the next release PR only shows new work. No file changes are expected. Merge with **Create a merge commit**." \
    --label release
  existing=$(gh pr list --repo "$GITHUB_REPOSITORY" --base staging --head master --state open --json number --jq '.[0].number')
else
  echo "Reusing open sync PR #$existing."
  if ! gh pr edit "$existing" --repo "$GITHUB_REPOSITORY" --add-label release; then
    echo "::warning::Could not add the release label to PR #$existing."
  fi
fi

# auto-merge needs "Allow auto-merge" in the repo settings; otherwise the PR waits for a click
if ! gh pr merge "$existing" --repo "$GITHUB_REPOSITORY" --merge --auto; then
  echo "::warning::Auto-merge is not available; merge PR #$existing by hand."
fi

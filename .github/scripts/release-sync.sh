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

# The label is created only when missing, so a maintainer's colour and description survive.
err_file="$RUNNER_TEMP/gh-error.txt"
if ! gh api "repos/$GITHUB_REPOSITORY/labels/release" --silent 2> "$err_file"; then
  if ! grep -q 'HTTP 404' "$err_file"; then
    cat "$err_file" >&2
    exit 1
  fi
  gh label create release --repo "$GITHUB_REPOSITORY" --color 0E8A16 \
    --description "Release and sync pull requests"
fi

existing=$(gh pr list --repo "$GITHUB_REPOSITORY" --base staging --head master --state open --json number --jq '.[0].number // ""')
if [ -z "$existing" ]; then
  # gh prints the new PR's URL; its last path segment is the number
  url=$(gh pr create --repo "$GITHUB_REPOSITORY" --base staging --head master \
    --title "Sync master into staging" \
    --body "Brings the release squash commit into staging's history, so the next release PR only shows new work. No file changes are expected. Merge with **Create a merge commit**." \
    --label release | tail -n 1)
  existing="${url##*/}"
  case "$existing" in
    ''|*[!0-9]*) echo "::error::Could not read the sync PR number from '$url'."; exit 1 ;;
  esac
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

#!/usr/bin/env bash
# Succeeds only when the deploy-production job of the CI & Deploy workflow (main.yml) succeeded
# for the master commit TARGET_SHA.
# Env: GH_TOKEN, GITHUB_REPOSITORY, TARGET_SHA
set -euo pipefail

runs=$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/main.yml/runs?head_sha=$TARGET_SHA&event=push&branch=master&per_page=20" \
  --jq '.workflow_runs[].id')
for run in $runs; do
  deployed=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$run/jobs?per_page=100" \
    --jq '[.jobs[] | select(.name == "deploy-production" and .conclusion == "success")] | length')
  if [ "$deployed" != "0" ]; then
    echo "deploy-production succeeded for $TARGET_SHA (run $run)."
    exit 0
  fi
done
echo "::error::production has not been deployed for $TARGET_SHA"
exit 1

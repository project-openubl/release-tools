#!/usr/bin/env bash
# Waits for the release workflow (release.yml) that a published release started in a
# repository, and fails if it fails.
#
#   wait-for-release-run.sh <owner/repo> <tag>
#
# A run that already failed (e.g. on a rerun of release-xhandler) is rerun. Needs GH_TOKEN with
# actions read and write on the repository.
set -euo pipefail
repo=$1 tag=$2

# The run of a `release` event has the tag as its branch; it takes a few seconds to appear
for _ in $(seq 60); do
  run=$(gh run list --repo "$repo" --workflow release.yml --event release --branch "$tag" \
    --limit 1 --json databaseId --jq '.[0].databaseId // empty')
  [ -n "$run" ] && break
  sleep 10
done
if [ -z "${run:-}" ]; then
  echo "::error::No release workflow run for $repo $tag"
  exit 1
fi

if [ "$(gh run view "$run" --repo "$repo" --json conclusion --jq .conclusion)" = failure ]; then
  echo "Rerunning the failed jobs of https://github.com/$repo/actions/runs/$run"
  gh run rerun "$run" --repo "$repo" --failed
  sleep 10
fi

echo "Waiting for https://github.com/$repo/actions/runs/$run"
gh run watch "$run" --repo "$repo" --exit-status --interval 30 >/dev/null

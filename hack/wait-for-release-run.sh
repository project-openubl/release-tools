#!/usr/bin/env bash
# Waits for the release workflow (release.yml, run-name "Release <tag>") of a repository's
# release <tag>, and fails if it fails.
#
#   wait-for-release-run.sh <owner/repo> <tag>
#
# Only runs created after the release count, so an older run for a deleted release of the same
# tag is ignored. A failed run is not re-run: a re-run uses the workflow file of the tagged
# commit, so a bug in it would just repeat. Instead the workflow is dispatched once from the
# default branch (`-f tag=<tag>`), which builds the same tag with the current workflow file.
#
# Waits up to 45 minutes, inside the 1-hour life of the GitHub App token: rerunning
# the release continues waiting. Needs GH_TOKEN with actions read and write.
#
# For a release workflow that can take longer, call it again with a new token: when it gives up,
# it writes timed_out=true and dispatched_at to $GITHUB_OUTPUT, and DISPATCHED_AT=<dispatched_at>
# continues from there (without dispatching the workflow a second time).
set -euo pipefail
repo=$1 tag=$2

since=$(gh api "repos/$repo/releases/tags/$tag" --jq .created_at)
default_branch=$(gh api "repos/$repo" --jq .default_branch)

# The newest run of release.yml for <tag> created at or after <time>, as "<id> <status> <conclusion>"
latest_run() {
  gh run list --repo "$repo" --workflow release.yml --limit 50 \
    --json databaseId,displayTitle,createdAt,status,conclusion \
    --jq "[.[] | select(.displayTitle == \"Release $tag\" and .createdAt >= \"$1\")]
          | sort_by(.createdAt) | last // empty | \"\(.databaseId) \(.status) \(.conclusion)\""
}

dispatched_at=${DISPATCHED_AT:-}
waiting_since=$SECONDS
deadline=$((SECONDS + 45 * 60))
while [ "$SECONDS" -lt "$deadline" ]; do
  found=$(latest_run "${dispatched_at:-$since}")
  read -r run status conclusion <<<"$found" || true

  if [ -z "$found" ]; then
    # The run of a published release or a dispatch takes a few seconds to appear
    if [ $((SECONDS - waiting_since)) -gt 300 ]; then
      echo "::error::No release workflow run for $repo $tag"
      exit 1
    fi
  elif [ "$status" != completed ]; then
    :
  elif [ "$conclusion" = success ]; then
    echo "$repo $tag released: https://github.com/$repo/actions/runs/$run"
    exit 0
  elif [ -n "$dispatched_at" ]; then
    echo "::error::The release workflow of $repo $tag failed again ($conclusion): https://github.com/$repo/actions/runs/$run"
    exit 1
  else
    echo "The release workflow of $repo $tag ended with $conclusion (https://github.com/$repo/actions/runs/$run): dispatching it from $default_branch"
    # A minute early, in case the runner's clock is ahead of GitHub's
    dispatched_at=$(date -u -d '-1 minute' +%Y-%m-%dT%H:%M:%SZ)
    gh workflow run release.yml --repo "$repo" --ref "$default_branch" -f tag="$tag"
    waiting_since=$SECONDS
  fi
  sleep 30
done

echo "::error::The release workflow of $repo $tag is still running after 45 minutes: rerun the release to keep waiting"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "timed_out=true" >> "$GITHUB_OUTPUT"
  echo "dispatched_at=$dispatched_at" >> "$GITHUB_OUTPUT"
fi
exit 1

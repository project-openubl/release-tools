#!/usr/bin/env bash
# Merges the pull request of <head> once the branch's required checks pass (GitHub auto-merge:
# the repository's branch protection decides what must pass), deletes <head> and prints the
# merge commit.
#
#   merge-pr.sh <head>
#
# Waits up to 45 minutes, inside the 1-hour life of the GitHub App token: rerunning
# release-xhandler continues waiting. Needs GH_TOKEN.
set -euo pipefail
head=$1

gh pr merge "$head" --auto --squash >&2

deadline=$((SECONDS + 45 * 60))
while [ "$SECONDS" -lt "$deadline" ]; do
  state=$(gh pr view "$head" --json state --jq .state)
  case "$state" in
  MERGED)
    merge_commit=$(gh pr view "$head" --json mergeCommit --jq .mergeCommit.oid)
    # gh pr merge --delete-branch does nothing with --auto
    gh api -X DELETE "repos/{owner}/{repo}/git/refs/heads/$head" >&2 || true
    echo "$merge_commit"
    exit 0
    ;;
  CLOSED)
    echo "::error::The pull request of $head was closed without merging" >&2
    exit 1
    ;;
  esac
  sleep 30
done
echo "::error::The pull request of $head has not merged after 45 minutes: check its CI, then rerun release-xhandler" >&2
exit 1

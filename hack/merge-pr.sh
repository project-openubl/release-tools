#!/usr/bin/env bash
# Merges the pull request of <head> once the branch's required checks pass (GitHub auto-merge:
# the repository's branch protection decides what must pass) and prints the merge commit.
#
#   merge-pr.sh <head>
#
# Needs GH_TOKEN. Waits up to 2.5 hours.
set -euo pipefail
head=$1

gh pr merge "$head" --auto --squash --delete-branch >&2

for _ in $(seq 300); do
  state=$(gh pr view "$head" --json state --jq .state)
  case "$state" in
  MERGED)
    gh pr view "$head" --json mergeCommit --jq .mergeCommit.oid
    exit 0
    ;;
  CLOSED)
    echo "::error::The pull request of $head was closed without merging" >&2
    exit 1
    ;;
  esac
  sleep 30
done
echo "::error::The pull request of $head did not merge: check its CI" >&2
exit 1

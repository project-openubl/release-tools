#!/usr/bin/env bash
# Checks, before release-xhandler tags anything, that every repository can be released from
# <branch> (empty: each repository's default branch): the branch exists, CI is required on it
# (the sync pull requests merge on it) and CI passed on its head (which is what gets tagged).
# Reports every problem, not just the first.
#
#   preflight.sh <branch> <owner/repo>...
#
# Needs GH_TOKEN with read access to the repositories.
set -uo pipefail
requested_branch=$1
shift

failed=0
fail() {
  echo "::error::$1"
  failed=1
}

for repo in "$@"; do
  branch=${requested_branch:-$(gh api "repos/$repo" --jq .default_branch)}
  if ! gh api "repos/$repo/branches/$branch" >/dev/null 2>&1; then
    fail "$repo has no branch $branch"
    continue
  fi

  # Required checks come from branch protection or from rulesets
  required=$(
    gh api "repos/$repo/branches/$branch" --jq '.protection.required_status_checks.checks[]?.context'
    gh api "repos/$repo/rules/branches/$branch" --jq '.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context'
  )
  [ -n "$required" ] || fail "$repo $branch requires no status checks: the release merges pull requests on CI"
  [ "$(gh api "repos/$repo" --jq .allow_auto_merge)" = true ] || fail "$repo does not allow auto-merge"

  runs=$(gh api --paginate "repos/$repo/commits/$branch/check-runs" --jq '.check_runs[] | "\(.status) \(.conclusion) \(.name)"')
  pending=$(echo "$runs" | awk '$1 != "completed"' | cut -d' ' -f3-)
  failing=$(echo "$runs" | awk '$1 == "completed" && $2 !~ /^(success|skipped|neutral)$/' | cut -d' ' -f3-)
  [ -z "$pending" ] || fail "$repo $branch still runs: $(echo "$pending" | paste -sd, -)"
  [ -z "$failing" ] || fail "$repo $branch failed: $(echo "$failing" | paste -sd, -)"
done

exit "$failed"

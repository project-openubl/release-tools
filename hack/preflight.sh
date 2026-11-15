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

# gh api, retrying the transient failures of the GitHub API. Prints the response; on failure
# returns 4 for a 404 and otherwise 1, with GitHub's error on stderr. (It runs in command
# substitutions: the caller records the failure.)
api() {
  local out attempt
  for attempt in 1 2 3; do
    if out=$(gh api "$@" 2>&1); then
      printf '%s\n' "$out"
      return 0
    fi
    if [[ "$out" == *"HTTP 404"* ]]; then
      echo "gh api $*: $out" >&2
      return 4
    fi
    sleep $((attempt * 5))
  done
  echo "gh api $*: $out" >&2
  return 1
}

unreadable() {
  fail "Could not read $1 from the GitHub API (error above)"
}

for repo in "$@"; do
  branch=${requested_branch:-$(api "repos/$repo" --jq .default_branch)} || { unreadable "$repo"; continue; }

  api "repos/$repo/branches/$branch" >/dev/null
  case $? in
  0) ;;
  4)
    fail "$repo has no branch $branch"
    continue
    ;;
  *)
    unreadable "$repo $branch"
    continue
    ;;
  esac

  # Required checks come from branch protection or from rulesets
  protected=$(api "repos/$repo/branches/$branch" --jq '.protection.required_status_checks.checks[]?.context') || { unreadable "$repo $branch"; continue; }
  ruled=$(api "repos/$repo/rules/branches/$branch" --jq '.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context') || { unreadable "$repo $branch rules"; continue; }
  [ -n "$protected$ruled" ] || fail "$repo $branch requires no status checks: the release merges pull requests on CI"

  auto_merge=$(api "repos/$repo" --jq .allow_auto_merge) || { unreadable "$repo"; continue; }
  [ "$auto_merge" = true ] || fail "$repo does not allow auto-merge"

  runs=$(api --paginate "repos/$repo/commits/$branch/check-runs" --jq '.check_runs[] | "\(.status) \(.conclusion) \(.name)"') || { unreadable "$repo $branch checks"; continue; }
  pending=$(echo "$runs" | awk 'NF && $1 != "completed"' | cut -d' ' -f3-)
  failing=$(echo "$runs" | awk '$1 == "completed" && $2 !~ /^(success|skipped|neutral)$/' | cut -d' ' -f3-)
  [ -z "$pending" ] || fail "$repo $branch still runs: $(echo "$pending" | paste -sd, -)"
  [ -z "$failing" ] || fail "$repo $branch failed: $(echo "$failing" | paste -sd, -)"
done

exit "$failed"

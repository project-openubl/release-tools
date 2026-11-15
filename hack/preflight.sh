#!/usr/bin/env bash
# Checks, before release-xhandler tags anything, that every repository can be released from
# <branch> (empty: each repository's default branch): the branch exists, CI is required on it
# (the sync pull requests merge on it) and every required check passed on its head (which is
# what gets tagged). Other checks on the head, e.g. a failed release run, don't count.
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

# gh api, retrying server and network failures. Prints the response; on failure returns 4 for a
# 404 and otherwise 1, with GitHub's error on stderr. (It runs in command substitutions: the
# caller records the failure.)
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
    # Other client errors don't get better by retrying
    [[ "$out" =~ HTTP\ 4[0-9][0-9] ]] && break
    sleep $((attempt * 5))
  done
  echo "gh api $*: $out" >&2
  return 1
}

unreadable() {
  fail "Could not read $1 from the GitHub API (error above)"
}

for repo in "$@"; do
  branch=${requested_branch:-$(api "repos/$repo" --jq .default_branch)} || {
    unreadable "$repo"
    continue
  }

  # A renamed branch redirects to its new name: that is not the branch asked for
  name=$(api "repos/$repo/branches/$branch" --jq .name)
  case $? in
  0) ;;
  4) name="" ;;
  *)
    unreadable "$repo $branch"
    continue
    ;;
  esac
  if [ "$name" != "$branch" ]; then
    fail "$repo has no branch $branch"
    continue
  fi

  # Required checks come from branch protection or from rulesets
  required=$(
    api "repos/$repo/branches/$branch" --jq '.protection.required_status_checks.checks[]?.context' &&
      api "repos/$repo/rules/branches/$branch" --jq '.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context'
  ) || {
    unreadable "$repo $branch protection"
    continue
  }
  required=$(echo "$required" | sed '/^$/d' | sort -u)
  if [ -z "$required" ]; then
    fail "$repo $branch requires no status checks: the release merges pull requests on CI"
    continue
  fi

  auto_merge=$(api "repos/$repo" --jq .allow_auto_merge) || {
    unreadable "$repo"
    continue
  }
  [ "$auto_merge" = true ] || fail "$repo does not allow auto-merge"

  # The latest run of each check on the head, as "<name>\t<status>\t<conclusion>"
  head=$(api "repos/$repo/commits/$branch" --jq .sha) || {
    unreadable "$repo $branch head"
    continue
  }
  checks=$(gh api --paginate --slurp "repos/$repo/commits/$head/check-runs" 2>&1 |
    jq -r '[.[].check_runs[]] | group_by(.name)[] | max_by(.started_at) | [.name, .status, .conclusion // ""] | @tsv') || {
    echo "$checks" >&2
    unreadable "$repo $branch checks"
    continue
  }
  while IFS= read -r check; do
    line=$(awk -F'\t' -v name="$check" '$1 == name' <<<"$checks")
    if [ -z "$line" ]; then
      fail "$repo $branch has not run the required check $check"
    elif [ "$(cut -f2 <<<"$line")" != completed ]; then
      fail "$repo $branch still runs the required check $check"
    elif [ "$(cut -f3 <<<"$line")" != success ]; then
      fail "$repo $branch failed the required check $check ($(cut -f3 <<<"$line"))"
    fi
  done <<<"$required"
done

exit "$failed"

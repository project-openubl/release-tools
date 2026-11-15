#!/usr/bin/env bash
# Commits the changes of the current checkout as the bot on <head> and opens a pull request
# into <base>. When a pull request of <head> is already open (a rerun), it is left as is:
# rebuilding and force-pushing <head> would drop the commits added to fix it.
#
#   open-pr.sh <head> <base> <title> <body>
#
# Needs GH_TOKEN (the bot App token) and BOT (its login, e.g. openubl-bot[bot]).
set -euo pipefail
head=$1 base=$2 title=$3 body=$4

open_pr=$(gh pr list --head "$head" --state open --json url --jq '.[].url')
if [ -n "$open_pr" ]; then
  echo "$open_pr is already open: keeping it as is"
  exit 0
fi

git config user.name "$BOT"
git config user.email "$(gh api "/users/$BOT" --jq .id)+$BOT@users.noreply.github.com"
git checkout -B "$head"
git add -A
git commit -q -m "$title"
# Replaces a branch left by a closed pull request
git push -q --force origin "$head"
gh pr create --head "$head" --base "$base" --title "$title" --body "$body"

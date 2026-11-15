#!/usr/bin/env bash
# Commits the changes of the current checkout as the bot on <head> and opens a pull request
# into <base>, unless one is open. Pushing again updates it, so a rerun is safe.
#
#   open-pr.sh <head> <base> <title> <body>
#
# Needs GH_TOKEN (the bot App token) and BOT (its login, e.g. openubl-bot[bot]).
set -euo pipefail
head=$1 base=$2 title=$3 body=$4

git config user.name "$BOT"
git config user.email "$(gh api "/users/$BOT" --jq .id)+$BOT@users.noreply.github.com"
git checkout -B "$head"
git add -A
git commit -q -m "$title"
git push -q --force origin "$head"

if [ -z "$(gh pr list --head "$head" --state open --json number --jq '.[].number')" ]; then
  gh pr create --head "$head" --base "$base" --title "$title" --body "$body"
fi

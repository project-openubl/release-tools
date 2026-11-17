#!/usr/bin/env bash
# Opens the pull request that adds an operator bundle to a community catalog
# (k8s-operatorhub/community-operators or redhat-openshift-ecosystem/community-operators-prod),
# from our fork of it:
#
#   operatorhub-pr.sh <upstream owner/repo> <fork owner/repo> <operator> <version> <bundle.tar.gz>
#
# - <version> is X.Y.Z. The bundle (a tarball with one top directory: manifests/, metadata/) goes
#   to operators/<operator>/<version>.
# - spec.replaces is set to the catalog's latest version (the catalogs use replaces-mode), so the
#   bundle upgrades from it. A version lower than the catalog's latest (a patch of an older line)
#   is not added: it would be a second head of the channel. Neither is a version while the pull
#   request of another version is open (it fails: merge that one, then rerun).
# - A catalog without the operator gets a ci.yaml with REVIEWERS (space separated): the catalog
#   merges a pull request by itself when its author is a reviewer and its tests pass.
# - OPENSHIFT_VERSIONS (e.g. v4.16, the oldest supported OpenShift) sets the bundle's
#   com.redhat.openshift.versions, for the OpenShift catalog.
#
# Does nothing when the catalog has the version or the pull request is open, so rerunning is safe.
# Needs GH_TOKEN: a classic token (public_repo, workflow) of a user who is a reviewer, since the pull
# request is opened in a repository outside the organization. workflow: syncing the fork brings in
# changes to the catalog's workflows.
set -euo pipefail
upstream=$1 fork=$2 operator=$3 version=$4 bundle=$5
bundle=$(realpath "$bundle")

dir="operators/$operator/$version"
branch="$operator-$version"

# exists <api path>: 0 if found, 1 if not (404); other errors stop the script
exists() {
  local out
  if out=$(gh api "$1" 2>&1); then return 0; fi
  [[ "$out" == *"HTTP 404"* ]] && return 1
  echo "::error::gh api $1: $out"
  exit 1
}

if exists "repos/$upstream/contents/$dir"; then
  echo "::notice::$upstream already has $dir"
  exit 0
fi
open_pr=$(gh pr list --repo "$upstream" --head "$branch" --state open --json url,headRepositoryOwner \
  --jq ".[] | select(.headRepositoryOwner.login == \"${fork%%/*}\") | .url")
if [ -n "$open_pr" ]; then
  echo "::notice::$open_pr is already open"
  exit 0
fi

# A channel has a single head: the bundle must replace the catalog's latest version, so the pull
# request of an earlier version has to merge first
user=$(gh api user --jq .login)
pending=$(gh pr list --repo "$upstream" --state open --author "$user" --limit 100 --json headRefName,url \
  --jq ".[] | select(.headRefName | startswith(\"$operator-\")) | .url")
if [ -n "$pending" ]; then
  echo "::error::Merge the open pull request of $operator first, then rerun the release: $pending"
  exit 1
fi

# The versions in the catalog
existing=""
if exists "repos/$upstream/contents/operators/$operator"; then
  existing=$(gh api "repos/$upstream/contents/operators/$operator" --jq '.[] | select(.type == "dir") | .name' |
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true)
fi
latest=$(printf '%s\n' "$existing" | sed '/^$/d' | sort -V | tail -1)
if [ -n "$latest" ] && [ "$(printf '%s\n' "$latest" "$version" | sort -V | tail -1)" != "$version" ]; then
  echo "::warning::$upstream has $operator $latest: $version, of an older line, would be a second head of the channel, so it is not added"
  exit 0
fi
previous=$latest

# The fork's default branch at upstream's, so the shallow clone below can push: GitHub only takes
# the new commit when it already has its parent. Nobody commits to the fork's default branch, so
# it fast-forwards; a fork that diverged anyway is reset to upstream.
base=$(gh api "repos/$upstream" --jq .default_branch)
if ! gh api -X POST "repos/$fork/merge-upstream" -f branch="$base" >/dev/null; then
  echo "::warning::$fork $base could not fast-forward to $upstream: resetting it"
  upstream_sha=$(gh api "repos/$upstream/commits/$base" --jq .sha)
  gh api -X PATCH "repos/$fork/git/refs/heads/$base" -f sha="$upstream_sha" -F force=true >/dev/null
fi

work=$(mktemp -d)
git clone -q --depth 1 --filter=blob:none --sparse --branch "$base" \
  "https://x-access-token:$GH_TOKEN@github.com/$fork.git" "$work"
cd "$work"
git sparse-checkout set "operators/$operator"

mkdir -p "$dir"
tar -xzf "$bundle" -C "$dir" --strip-components=1
csv=$(ls "$dir"/manifests/*.clusterserviceversion.yaml)
if [ -n "$previous" ]; then
  yq -i ".spec.replaces = \"$operator.v$previous\"" "$csv"
else
  yq -i 'del(.spec.replaces)' "$csv"
fi

if [ ! -f "operators/$operator/ci.yaml" ]; then
  {
    echo "---"
    echo "# Use \`replaces-mode\` or \`semver-mode\`."
    echo "updateGraph: replaces-mode"
    echo "reviewers:"
    for reviewer in ${REVIEWERS:?REVIEWERS is needed for a catalog without $operator}; do
      echo "  - $reviewer"
    done
  } > "operators/$operator/ci.yaml"
fi

if [ -n "${OPENSHIFT_VERSIONS:-}" ]; then
  yq -i ".annotations.\"com.redhat.openshift.versions\" = \"$OPENSHIFT_VERSIONS\"" "$dir/metadata/annotations.yaml"
  if [ -f "$dir/bundle.Dockerfile" ]; then
    echo "LABEL com.redhat.openshift.versions=\"$OPENSHIFT_VERSIONS\"" >> "$dir/bundle.Dockerfile"
  fi
fi

git config user.name "$user"
git config user.email "$(gh api user --jq .id)+$user@users.noreply.github.com"
git checkout -q -b "$branch"
git add "operators/$operator"
git commit -q -s -m "operator $operator ($version)"
# Replaces a branch left by a closed pull request
git push -q --force origin "$branch"

body="Adds $operator $version"
[ -n "$previous" ] && body+=", which replaces $previous"
body+=".${RUN_URL:+ Opened by [the release workflow]($RUN_URL).}"
gh pr create --repo "$upstream" --base "$base" --head "${fork%%/*}:$branch" \
  --title "operator $operator ($version)" --body "$body"

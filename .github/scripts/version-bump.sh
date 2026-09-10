#!/usr/bin/env bash
set -euo pipefail

# Run only in the disposable Actions checkout. All rebuilds start at current main.
git fetch origin main
base=$(git rev-parse FETCH_HEAD)
git checkout --detach "$base"
current=$(jq -er '.version' plugin.json)
version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
[[ $current =~ $version_pattern ]] || { echo "Invalid version: $current" >&2; exit 1; }
git config user.name 'github-actions[bot]'
git config user.email 'github-actions[bot]@users.noreply.github.com'

rebuild() {
    local branch=$1 target=$2 lease=$3
    git checkout --detach "$base"
    jq --arg v "$target" '.version = $v' plugin.json > plugin.json.tmp
    mv plugin.json.tmp plugin.json
    git add plugin.json
    git commit -m "Bump version to $target"
    git push "--force-with-lease=refs/heads/$branch:$lease" origin "HEAD:refs/heads/$branch"
    gh workflow run ci.yml --ref "$branch"
}

# Paginate rather than silently ignoring older open PRs. Forks and human PRs
# must never authorize a force-push to an origin branch.
prs=$(gh api --paginate "repos/$GITHUB_REPOSITORY/pulls?state=open&base=main&per_page=100")
pending=$(jq -r --arg repo "$GITHUB_REPOSITORY" '
    .[] | select(.user.login == "github-actions[bot]" and .user.type == "Bot")
    | select(.head.repo.full_name == $repo)
    | select(.head.ref | startswith("chore/bump-v"))
    | [.number, .head.ref, .head.sha] | @tsv' <<< "$prs")
has_pending=false
while IFS=$'\t' read -r number branch lease; do
    [[ -n $number ]] || continue
    target=${branch#chore/bump-v}
    [[ $target =~ $version_pattern ]] || continue
    newest=$(printf '%s\n' "$current" "$target" | sort -V | tail -n 1)
    if [[ $newest == "$current" ]]; then
        gh pr close "$number" --comment "Superseded by version $current on main."
    else
        rebuild "$branch" "$target" "$lease"
        has_pending=true
    fi
done <<< "$pending"

# A newer main may have landed while this run waited for CI or the job lock.
# Its own push run must decide whether that commit needs a new bump.
if [[ ${CREATE_BUMP:-false} == true && $has_pending == false && $base == "$GITHUB_SHA" ]]; then
    IFS='.' read -r major minor patch <<< "$current"
    target="$major.$minor.$((patch + 1))"
    branch="chore/bump-v$target"
    # An empty explicit lease permits creation only, never replacing an
    # existing branch without a verified open bot PR.
    rebuild "$branch" "$target" ''
    gh pr create --base main --head "$branch" \
        --title "Bump version to $target" \
        --body "Automated patch version bump: \`$current\` → \`$target\`"
fi

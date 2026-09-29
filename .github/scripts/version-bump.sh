#!/usr/bin/env bash
set -euo pipefail

# Disposable Actions checkout only. Never force-push main or reset user work.
[[ ${PR_NUMBER:-} =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid PR number' >&2; exit 1; }
marker="Version-Bump-PR: $PR_NUMBER"
for attempt in {1..10}; do
    git fetch origin main
    base=$(git rev-parse FETCH_HEAD)
    if git log "$base" --format=%B | grep -Fx "$marker" > /dev/null; then
        echo "PR #$PR_NUMBER already bumped"
        exit 0
    fi
    git checkout --detach "$base"
    current=$(jq -er '.version' plugin.json)
    [[ $current =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
        echo "Invalid version: $current" >&2; exit 1;
    }
    IFS='.' read -r major minor patch <<< "$current"
    target="$major.$minor.$((patch + 1))"
    jq --arg v "$target" '.version = $v' plugin.json > plugin.json.tmp
    mv plugin.json.tmp plugin.json
    git add plugin.json
    git -c user.name='github-actions[bot]' -c user.email='github-actions[bot]@users.noreply.github.com' \
        commit -m "Bump version to $target" -m "$marker"
    if git push origin HEAD:refs/heads/main; then
        echo "PR #$PR_NUMBER bumped $current to $target"
        exit 0
    fi
    # Another merge or bump won the race. Recompute from the new main.
    sleep "$attempt"
done
echo 'Could not push version bump after 10 attempts; rerun this workflow' >&2
exit 1

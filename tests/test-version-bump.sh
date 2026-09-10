#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
export GITHUB_REPOSITORY=owner/repo CREATE_BUMP=false
export PRS="$TMP/prs" CALLS="$TMP/calls"
mkdir "$TMP/bin"
cat > "$TMP/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$CALLS"
if [[ $1 == api ]]; then
    [[ $2 == --paginate ]]
    cat "$PRS"
fi
MOCK
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
git init -q --bare "$TMP/origin.git"
git init -q -b main "$TMP/work"
cd "$TMP/work"
git remote add origin "$TMP/origin.git"
printf '{"version":"0.1.6","name":"test"}\n' > plugin.json
git add plugin.json
git commit -qm initial
old=$(git rev-parse HEAD)
git push -q origin HEAD:main HEAD:chore/bump-v0.1.9
printf '{"version":"0.1.8","name":"test"}\n' > plugin.json
printf 'current main content\n' > source
git add plugin.json source
git commit -qm 'manual version bump'
export GITHUB_SHA
GITHUB_SHA=$(git rev-parse HEAD)
git push -q origin HEAD:main

pr() {
    jq -nc --argjson number "$1" --arg target "$2" --arg sha "$3" \
        --arg login "${4:-github-actions[bot]}" --arg repo "${5:-owner/repo}" \
        '{number:$number,user:{login:$login,type:"Bot"},head:{ref:("chore/bump-v"+$target),sha:$sha,repo:{full_name:$repo}}}'
}
run() {
    : > "$CALLS"
    bash "$ROOT/.github/scripts/version-bump.sh"
}
called() { grep -Fqx -- "$*" "$CALLS"; }
remote_sha() { git --git-dir="$TMP/origin.git" rev-parse "refs/heads/$1"; }

{
    pr 1 0.1.7 "$old"
    pr 2 0.1.8 "$old"
    pr 3 0.1.9 "$old"
    pr 4 0.1.5 "$old" human
    pr 5 0.1.4 "$old" 'github-actions[bot]' fork/repo
    pr 6 invalid "$old"
} | jq -s . > "$PRS"
# A second API page must also be processed.
pr 7 0.1.3 "$old" | jq -s . >> "$PRS"
run
called 'pr close 1 --comment Superseded by version 0.1.8 on main.'
called 'pr close 2 --comment Superseded by version 0.1.8 on main.'
called 'pr close 7 --comment Superseded by version 0.1.8 on main.'
if grep -Eq '^pr close (4|5|6) ' "$CALLS"; then exit 1; fi
rebuilt=$(remote_sha chore/bump-v0.1.9)
[[ $(git rev-parse "$rebuilt^") == "$GITHUB_SHA" ]]
[[ $(git show "$rebuilt:plugin.json" | jq -r .version) == 0.1.9 ]]
[[ $(git diff-tree --no-commit-id --name-only -r "$rebuilt") == plugin.json ]]
called 'workflow run ci.yml --ref chore/bump-v0.1.9'
if grep -q '^pr create ' "$CALLS"; then exit 1; fi
echo 'PASS: manual bump cleanup, pagination, bot/fork scoping, and rebuild from current main'

# The API snapshot precedes a concurrent update of the remote branch.
pr 3 0.1.9 "$rebuilt" | jq -s . > "$PRS"
git commit -qm concurrent --allow-empty
concurrent=$(git rev-parse HEAD)
git push -q origin HEAD:chore/bump-v0.1.9
if run; then
    echo 'FAIL: stale lease accepted' >&2
    exit 1
fi
[[ $(remote_sha chore/bump-v0.1.9) == "$concurrent" ]]
if grep -q '^workflow run ' "$CALLS"; then exit 1; fi
echo 'PASS: stale lease rejects concurrent branch updates'

printf '[]\n' > "$PRS"
run
if grep -q '^pr create ' "$CALLS"; then exit 1; fi
export CREATE_BUMP=true
GITHUB_SHA=$old
run
if grep -q '^pr create ' "$CALLS"; then exit 1; fi
GITHUB_SHA=$(git rev-parse origin/main)
# Creation must not overwrite an existing branch without a verified bot PR.
if run; then
    echo 'FAIL: unverified branch overwritten' >&2
    exit 1
fi
[[ $(remote_sha chore/bump-v0.1.9) == "$concurrent" ]]
git push -q origin :chore/bump-v0.1.9
run
# shellcheck disable=SC2016
called 'pr create --base main --head chore/bump-v0.1.9 --title Bump version to 0.1.9 --body Automated patch version bump: `0.1.8` → `0.1.9`'
[[ $(git rev-parse "$(remote_sha chore/bump-v0.1.9)^") == "$GITHUB_SHA" ]]
echo 'PASS: creation permission, stale-run guard, and creation-only lease'

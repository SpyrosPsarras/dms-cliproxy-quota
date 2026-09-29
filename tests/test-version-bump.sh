#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
git init -q --bare "$TMP/origin.git"
git init -q -b main "$TMP/work"
cd "$TMP/work"
git remote add origin "$TMP/origin.git"
printf '{"version":"0.1.9","name":"test"}\n' > plugin.json
git add plugin.json
git commit -qm initial
git push -q origin HEAD:main
run() { PR_NUMBER=$1 bash "$ROOT/.github/scripts/version-bump.sh"; }
version() { git --git-dir="$TMP/origin.git" show main:plugin.json | jq -r .version; }
remote_sha() { git --git-dir="$TMP/origin.git" rev-parse main; }

run 10
[[ $(version) == 0.1.10 ]]
first=$(remote_sha)
[[ $(git diff-tree --no-commit-id --name-only -r "$first") == plugin.json ]]
run 10
[[ $(remote_sha) == "$first" ]]
echo 'PASS: one patch bump, only plugin.json changed, rerun is a no-op'

# Jobs can arrive out of merge order; docs-only PRs also count.
printf 'docs update\n' > README.md
git add README.md
git commit -qm 'docs-only PR'
git push -q origin HEAD:main
run 12
run 11
run 12
[[ $(version) == 0.1.12 ]]
[[ $(git --git-dir="$TMP/origin.git" show main:README.md) == 'docs update' ]]
echo 'PASS: out-of-order merges each bump once and preserve other changes'

# Make main move just before the first push, using another checkout.
git clone -q -b main "$TMP/origin.git" "$TMP/racer"
printf 'concurrent content\n' > "$TMP/racer/source"
git -C "$TMP/racer" add source
git -C "$TMP/racer" commit -qm 'another merge'
export RACE_DIR="$TMP/racer" REAL_GIT
REAL_GIT=$(command -v git)
mkdir "$TMP/bin"
cat > "$TMP/bin/git" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == push && ! -e "$RACE_DIR/raced" ]]; then
    touch "$RACE_DIR/raced"
    "$REAL_GIT" -C "$RACE_DIR" push -q origin HEAD:main
fi
exec "$REAL_GIT" "$@"
MOCK
chmod +x "$TMP/bin/git"
PATH="$TMP/bin:$PATH" run 13
[[ $(version) == 0.1.13 ]]
[[ $(git --git-dir="$TMP/origin.git" show main:source) == 'concurrent content' ]]
echo 'PASS: rejected push retries from latest main without losing changes'

before=$(remote_sha)
if run invalid; then echo 'FAIL: invalid PR accepted' >&2; exit 1; fi
[[ $(remote_sha) == "$before" ]]
printf '{"version":"bad"}\n' > plugin.json
git add plugin.json
git commit -qm 'invalid version'
git push -q origin HEAD:main
before=$(remote_sha)
if run 14; then echo 'FAIL: invalid version accepted' >&2; exit 1; fi
[[ $(remote_sha) == "$before" ]]
echo 'PASS: invalid input leaves main untouched'

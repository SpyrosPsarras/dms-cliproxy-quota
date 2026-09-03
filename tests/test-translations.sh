#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: Node.js not available, skipping translation tests"
    exit 0
fi

node - "$SCRIPT_DIR" <<'NODE'
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const root = process.argv[2];
const catalogPath = path.join(root, "translations.js");
const catalogSource = fs.readFileSync(catalogPath, "utf8").replace(/^\.pragma library\s*/, "");
const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(catalogSource, sandbox, { filename: catalogPath });

const keys = new Set();
for (const filename of ["CliproxyQuotaWidget.qml", "CliproxyQuotaSettings.qml"]) {
    if (!fs.existsSync(path.join(root, filename)))
        continue;
    const source = fs.readFileSync(path.join(root, filename), "utf8");
    const pattern = /(?:root\.)?tr\("([^"]+)"\)/g;
    let match;
    while ((match = pattern.exec(source)) !== null)
        keys.add(match[1]);
}

let failed = false;
for (const key of [...keys].sort()) {
    const entry = sandbox.strings[key];
    for (const language of ["fr", "es"]) {
        if (!entry || typeof entry[language] !== "string" || entry[language].trim() === "") {
            console.error(`FAIL: missing ${language} translation for "${key}"`);
            failed = true;
        }
    }
}

if (sandbox.tr("a key nobody added", "fr") !== "a key nobody added") {
    console.error("FAIL: unknown key must fall back to the key itself");
    failed = true;
}
if (sandbox.tr("Quota", "de") !== "Quota") {
    console.error("FAIL: unknown language must fall back to the key");
    failed = true;
}

if (failed)
    process.exit(1);

console.log(`PASS: ${keys.size} UI keys have complete French and Spanish translations`);
console.log("PASS: tr() falls back safely for unknown keys and languages");
NODE

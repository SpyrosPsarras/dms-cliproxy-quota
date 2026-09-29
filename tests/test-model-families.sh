#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
node - "$ROOT/CliproxyQuotaWidget.qml" <<'NODE'
const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const source = fs.readFileSync(process.argv[2], 'utf8');
const context = vm.createContext({pillProvider: {provider: 'codex'}, familyPalette: ['a', 'b', 'c', 'd']});
vm.runInContext(source.match(/    function parseModel\(raw\) \{[\s\S]*?\n    \}/)[0], context);
for (const [provider, id, family, name] of [
    ['codex', 'gpt-6-astra', 'GPT Astra', 'GPT 6 Astra'],
    ['codex', 'gpt-6-sol', 'GPT Sol', 'GPT 6 Sol'],
    ['codex', 'gpt-6.1-sol', 'GPT Sol', 'GPT 6.1 Sol'],
    ['codex', 'gpt-5.6-sol', 'GPT Sol', 'GPT 5.6 Sol'],
    ['codex', 'gpt-5.6-luna', 'GPT Luna', 'GPT 5.6 Luna'],
    ['codex', 'gpt-6-luna', 'GPT Luna', 'GPT 6 Luna'],
    ['codex', 'gpt-5.5', 'GPT', 'GPT 5.5'],
    ['claude', 'claude-opus-4-1-20250805', 'Opus', 'Opus 4.1'],
    ['claude', 'claude-3-5-sonnet-20241022', 'Sonnet', 'Sonnet 3.5'],
    ['claude', 'claude-fable-5', 'Fable', 'Fable 5'],
    ['acme', 'acme-2.5-large', 'Large', 'Large 2.5'],
    ['acme', 'acme-small-2-1-fast-20250101', 'Small Fast', 'Small 2.1 Fast'],
    ['acme', 'acme-large', 'Large', 'Large'],
    ['acme', 'acme-2-1', '2.1', '2.1'],
    ['acme', '', '?', '?'],
]) {
    context.pillProvider = {provider};
    assert.deepStrictEqual({...context.parseModel(id)}, {family, name}, id);
}
context.pillProvider = {provider: 'codex'};
context.modelTotals = [
    {model: 'gpt-6-astra', total: 100},
    {model: 'gpt-6-sol', total: 20},
    {model: 'gpt-6.1-sol', total: 30},
    {model: 'gpt-6-luna', total: 10},
    {model: 'gpt-5.5', total: 5},
];
const families = vm.runInContext('(function() {' + source.match(/readonly property var modelFamilies: \{([\s\S]*?)\n    \}/)[1] + '})()', context);
assert.deepStrictEqual(Array.from(families, f => [f.family, f.total]), [
    ['GPT Astra', 100], ['GPT Sol', 50], ['GPT Luna', 10], ['GPT', 5],
]);
assert.equal(families[1].versions.length, 2);
assert.equal(new Set(families.map(f => f.color)).size, 4);
vm.runInContext(source.match(/    function familyTokens\(entry, family\) \{[\s\S]*?\n    \}/)[0], context);
const day = {tokens: Object.fromEntries(context.modelTotals.map(m => [m.model, m.total]))};
for (const family of families)
    assert.equal(context.familyTokens(day, family), family.total);
console.log('PASS: model families, display names, version grouping, colours and daily token totals');
NODE

#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
node - "$ROOT/CliproxyQuotaWidget.qml" <<'NODE'
const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const source = fs.readFileSync(process.argv[2], 'utf8');
const body = '(function() {' + source.match(/function revealFocused\(\) \{([\s\S]*?)\n                        \}/)[1] + '})()';
const context = {root: {focusedIndex: 7}, providerRow: {x: 0},
    providerTabs: {itemAt: () => ({x: 560, width: 140})},
    contentWidth: 700, width: 388, contentX: 0};
vm.runInNewContext(body, context);
assert.equal(context.contentX, 312);
context.providerTabs.itemAt = () => ({x: 0, width: 140});
vm.runInNewContext(body, context);
assert.equal(context.contentX, 0);
context.providerRow.x = 44;
context.contentWidth = 388;
vm.runInNewContext(body, context);
assert.equal(context.contentX, 0);
const expanded = source.match(/^\s+property bool expanded: (.*)/m)[1];
assert.equal(vm.runInNewContext(expanded, {healthy: true, modelData: {noQuota: true, error: 'provider API failed: 429'}}), true);
assert.equal(vm.runInNewContext(expanded, {healthy: true, modelData: {noQuota: true, error: ''}}), false);
const follow = '(function() {' + source.match(/function followActiveProvider\(\) \{([\s\S]*?)\n    \}/)[1] + '})()';
const saved = {};
const root = {visibleProviders: [{provider: 'claude', lastRequestEpoch: 100}, {provider: 'codex', lastRequestEpoch: 200}, {provider: 'idle', lastRequestEpoch: null}],
    activeProvider: 'codex', focusedProvider: 'claude', pluginService: {savePluginData: (_, k, v) => { saved[k] = v; }}};
const run = () => vm.runInNewContext(follow, root);
run();
assert.equal(root.focusedProvider, 'claude', 'manual focus holds while the active provider is unchanged');
root.visibleProviders[0].lastRequestEpoch = 300;
run();
assert.equal(root.focusedProvider, 'claude');
assert.equal(root.activeProvider, 'claude');
assert.deepEqual(saved, {activeProvider: 'claude', focusedProvider: 'claude'});
root.focusedProvider = 'idle';
root.visibleProviders[1].lastRequestEpoch = 400;
run();
assert.equal(root.focusedProvider, 'codex', 'a request on another provider moves the focus');
root.visibleProviders = [];
run();
assert.equal(root.focusedProvider, 'codex', 'no data keeps the focus');
console.log('PASS: tabs scroll both directions, short rows stay centered, quota errors expand, focus follows the active provider');
NODE

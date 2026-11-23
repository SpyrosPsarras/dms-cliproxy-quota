#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
node - "$ROOT/CliproxyQuotaWidget.qml" <<'NODE'
const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const source = fs.readFileSync(process.argv[2], 'utf8');
const binding = name => source.match(new RegExp(`^    readonly property var ${name}: (.*)$`, 'm'))[1];
const accounts = [{account: 'a@x', headline: false}, {account: 'b@x', headline: true}, {account: 'c@x', headline: false}];
assert.equal(vm.runInNewContext(binding('headlineAccount'), {pillProvider: {accounts}}).account, 'b@x', 'the quota card names the account behind it');
assert.deepEqual(vm.runInNewContext(binding('otherAccounts'), {pillProvider: {accounts}}).map(a => a.account), ['a@x', 'c@x'],
    'that account is not repeated in the list');
assert.equal(vm.runInNewContext(binding('headlineAccount'), {pillProvider: {accounts: [{account: 'a@x', headline: false}]}}), null,
    'no live account, no name on the quota card');
const detailFn = source.match(/^    function accountDetail\(account\) \{[\s\S]*?\n    \}/m)[0];
const detailCtx = {tr: k => k, ago: () => '2m ago', formatCount: n => String(n)};
vm.runInNewContext(detailFn + '; this.accountDetail = accountDetail;', detailCtx);
assert.equal(detailCtx.accountDetail({status: 'active', lastRequestAt: 't', success: 5, failed: 1}), 'last request 2m ago · 5 ok · 1 failed');
assert.equal(detailCtx.accountDetail({status: 'error', headline: true, success: 0, failed: 0}), 'error · 0 ok · 0 failed',
    'a non-active status shows on the quota card, which has no tag row');
const expanded = source.match(/^\s+readonly property bool expanded: (root\.expandedAccounts.*)/m)[1];
const card = (error, expandedAccounts = {}) => vm.runInNewContext(expanded, {root: {expandedAccounts}, expandKey: 'a1', modelData: {error}});
assert.equal(card('provider API failed: 429'), true, 'an account with an error opens');
assert.equal(card(''), false, 'a quiet account stays one line');
assert.equal(card('', {a1: true}), true, 'a manual expand survives the refresh');
assert.equal(card('provider API failed: 429', {a1: false}), false, 'a manual collapse survives the refresh');
const follow = '(function() {' + source.match(/function followActiveProvider\(\) \{([\s\S]*?)\n    \}/)[1] + '})()';
const saved = {};
const root = {interactionActive: false, visibleProviders: [{provider: 'claude', lastRequestEpoch: 100}, {provider: 'codex', lastRequestEpoch: 200}, {provider: 'idle', lastRequestEpoch: null}],
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
root.interactionActive = true;
root.visibleProviders[0].lastRequestEpoch = 500;
run();
assert.equal(root.focusedProvider, 'codex', 'the provider never switches under an open popout');
root.interactionActive = false;
run();
assert.equal(root.focusedProvider, 'claude', 'it follows once the popout closes');
root.visibleProviders = [];
run();
assert.equal(root.focusedProvider, 'claude', 'no data keeps the focus');
console.log('PASS: the quota card names its account, the list holds the others, quota errors expand, focus follows the active provider');
NODE

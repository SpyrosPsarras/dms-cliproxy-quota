#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
node - "$ROOT/CliproxyQuotaWidget.qml" <<'NODE'
const fs = require('fs');
const vm = require('vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(process.argv[2], 'utf8');
const first = '1111111111111111';
const second = '2222222222222222';
const accounts = [{authIndex: first}, {authIndex: second}];
const todayDate = '2026-11-19';
const today = {date: todayDate, requests: 9, failed: 2, tokens: {small: 120, large: 80}, accounts: {
    [first]: {requests: 4, failed: 1, tokens: {small: 70}},
    [second]: {requests: 3, failed: 1, tokens: {small: 20, large: 40}},
}};
const yesterday = {date: '2026-11-18', requests: 5, failed: 0, tokens: {small: 100}, accounts: {
    [second]: {requests: 2, failed: 0, tokens: {small: 50}},
}};
const older = {date: '2026-11-17', requests: 2, failed: 0, tokens: {small: 30}};
const context = vm.createContext({pillProvider: {accounts}, activity: [older, yesterday, today],
    selectedAccount: second, todayDate, tr: key => key, Theme: {}});
context.root = context;
function block(name) {
    const match = source.match(new RegExp(`^    readonly property (?:var|bool) ${name}: \\{([\\s\\S]*?)\\n    \\}`, 'm'));
    assert.ok(match, `${name} binding is missing`);
    return vm.runInContext(`(function() {${match[1]}})()`, context);
}
function runFunction(name) {
    const match = source.match(new RegExp(`^    function ${name}\\([^\\n]*\\) \\{[\\s\\S]*?\\n    \\}`, 'm'));
    assert.ok(match, `${name} function is missing`);
    vm.runInContext(match[0], context);
}
const plain = value => JSON.parse(JSON.stringify(value));
runFunction('dayTokens');
Object.defineProperty(context, 'viewActivity', {get() {
    runFunction('viewEntry');
    return block('viewActivity');
}});
assert.deepEqual(plain(block('usageStats')), [
    {label: 'Today', tokens: 60, requests: 3},
    {label: '7 days', tokens: 110, requests: 5},
], 'usage stats should count only the selected account');
assert.deepEqual(plain(context.viewEntry(today)), {
    date: todayDate, requests: 3, failed: 1, tokens: {small: 20, large: 40},
});
assert.deepEqual(plain(context.viewEntry(older)), {
    date: older.date, requests: 0, failed: 0, tokens: {},
});
context.selectedAccount = 'unknown';
assert.deepEqual(plain(context.viewEntry(today)), {
    date: todayDate, requests: 0, failed: 0, tokens: {},
});
context.selectedAccount = '';
assert.equal(context.viewEntry(today), today);
assert.deepEqual(plain(block('usageStats')), [
    {label: 'Today', tokens: 200, requests: 9},
    {label: '7 days', tokens: 330, requests: 16},
], 'All keeps the provider totals, including unattributed usage');

const palette = source.match(/readonly property var accountPalette: (\[[\s\S]*?\n    \])/);
assert.ok(palette, 'accountPalette binding is missing');
context.accountPalette = vm.runInContext(palette[1], context);
Object.defineProperty(context, 'accountColors', {get: () => block('accountColors')});
context.pillProvider = {accounts: [accounts[0]]};
assert.deepEqual(plain(context.accountColors), {});
assert.equal(block('showAccountSplit'), false);
context.pillProvider = {accounts: [accounts[1], accounts[0]]};
assert.deepEqual(plain(context.accountColors), {
    [second]: context.accountPalette[0], [first]: context.accountPalette[1],
});
assert.notEqual(context.accountColors[first], context.accountColors[second]);
assert.equal(block('showAccountSplit'), true);
context.activity = [older];
assert.equal(block('showAccountSplit'), false);
context.activity = [older, {...today, accounts: {
    [first]: {requests: 4, failed: 1, tokens: {}},
    [second]: {requests: 3, failed: 1, tokens: {}},
}}];
assert.equal(block('showAccountSplit'), false, 'old bridges report account requests but no account tokens');

runFunction('familyTokens');
runFunction('accountTokens');
assert.equal(context.accountTokens(today, second, null), 60);
assert.equal(context.accountTokens(today, second, {ids: ['small', 'absent']}), 20);
assert.equal(context.accountTokens(older, second, null), 0);
assert.equal(context.accountTokens(today, 'unknown', {ids: ['small']}), 0);

runFunction('clampedBoxes');
assert.deepEqual(plain(context.clampedBoxes(100, [{authIndex: 'a1', value: 70}, {authIndex: 'b2', value: 50}])), [
    {authIndex: 'a1', value: 70}, {authIndex: 'b2', value: 30},
]);
assert.deepEqual(plain(context.clampedBoxes(100, [{authIndex: 'a1', value: 20}])), [{authIndex: 'a1', value: 20}]);
assert.deepEqual(plain(context.clampedBoxes(100, [{authIndex: 'a1', value: -20}, {authIndex: 'b2', value: 120}])), [
    {authIndex: 'a1', value: 0}, {authIndex: 'b2', value: 100},
]);

const providerChanged = source.match(/^    onPillProviderChanged: \{([\s\S]*?)\n    \}/m);
assert.ok(providerChanged, 'account selection must react to an account refresh');
context.pillProvider = {accounts};
context.selectedAccount = second;
vm.runInContext(providerChanged[1], context);
assert.equal(context.selectedAccount, second, 'keep a selection on refresh if the account remains');
context.pillProvider = {accounts: [accounts[0]]};
vm.runInContext(providerChanged[1], context);
assert.equal(context.selectedAccount, '', 'reset the selection when the account disappears');

const focusChanged = source.match(/^    onFocusedProviderIdChanged: (.+)$/m);
assert.ok(focusChanged, 'account selection must react to a provider change');
context.selectedAccount = second;
vm.runInContext(focusChanged[1], context);
assert.equal(context.selectedAccount, '', 'reset the selection when the provider changes');

const opened = source.match(/^                function onOpened\(\) \{([\s\S]*?)\n                \}/m);
assert.ok(opened, 'account selection must react to opening the popout');
context.Qt = {callLater: () => {}};
context.selectedAccount = second;
vm.runInContext(opened[1], context);
assert.equal(context.selectedAccount, '', 'reset the selection when the popout opens');
console.log('PASS: account colours, split availability, filtered usage, account reset and clamped boxes');
NODE

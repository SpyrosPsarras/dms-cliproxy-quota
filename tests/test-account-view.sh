#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
node - "$ROOT/CliproxyQuotaWidget.qml" <<'NODE'
const fs = require('fs');
const vm = require('vm');
const assert = require('node:assert/strict');
const test = require('node:test');
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

runFunction('familyTokens');
runFunction('familyViewTotal');
const family = {ids: ['small', 'large', 'absent']};
assert.equal(context.familyViewTotal(family), 330, 'All includes unattributed tokens');
context.selectedAccount = second;
assert.equal(context.familyViewTotal(family), 110, 'the selected account contributes only its own tokens');
assert.equal(context.familyViewTotal({ids: ['small']}), 70, 'only models in the family are counted');
context.selectedAccount = '';

const palette = source.match(/readonly property var accountPalette: (\[[\s\S]*?\n    \])/);
assert.ok(palette, 'accountPalette binding is missing');
context.accountPalette = vm.runInContext(palette[1], context);
assert.deepEqual(plain(context.accountPalette), ['#e6e1e5', '#ff6ec7', '#00e5ff', '#c6ff00', '#ff9100']);
context.Theme.surfaceText = '#fafafa';
assert.equal(vm.runInContext(palette[1], context)[0], context.Theme.surfaceText);
Object.defineProperty(context, 'accountColors', {get: () => block('accountColors')});
Object.defineProperty(context, 'showAccountSplit', {get: () => block('showAccountSplit')});
runFunction('hasAccountTokens');
runFunction('cardAccountColor');
const cardColorBinding = source.match(/^                                readonly property var accountColor: (.+)$/m);
assert.ok(cardColorBinding, 'account card colour binding is missing');
context.modelData = accounts[0];
const cardColor = () => vm.runInContext(cardColorBinding[1], context);
context.pillProvider = {accounts: [accounts[0]]};
assert.deepEqual(plain(context.accountColors), {});
assert.equal(block('showAccountSplit'), false);
context.pillProvider = {accounts: [accounts[1], accounts[0]]};
assert.deepEqual(plain(context.accountColors), {
    [second]: context.accountPalette[0], [first]: context.accountPalette[1],
});
assert.notEqual(context.accountColors[first], context.accountColors[second]);
assert.equal(block('showAccountSplit'), true);
assert.equal(cardColor(), '#ff6ec7', 'account cards use their palette colour when the split is available');
context.activity = [older];
assert.equal(block('showAccountSplit'), false);
context.activity = [older, {...today, accounts: {
    [first]: {requests: 4, failed: 1, tokens: {}},
    [second]: {requests: 3, failed: 1, tokens: {}},
}}];
assert.equal(block('showAccountSplit'), false, 'old bridges report account requests but no account tokens');
assert.equal(cardColor(), '', 'account cards use the legacy border when the bridge supplies no account tokens');

runFunction('accountTokens');
assert.equal(context.accountTokens(today, second, null), 60);
assert.equal(context.accountTokens(today, second, {ids: ['small', 'absent']}), 20);
assert.equal(context.accountTokens(older, second, null), 0);
assert.equal(context.accountTokens(today, 'unknown', {ids: ['small']}), 0);

runFunction('clampedBoxes');
runFunction('accountBoxes');
Object.defineProperty(context, 'splitAccounts', {get: () => block('splitAccounts')});
assert.deepEqual(plain(context.accountBoxes(200, [today], null)), [
    {authIndex: second, value: 60}, {authIndex: first, value: 70},
]);
context.selectedAccount = second;
assert.deepEqual(plain(context.accountBoxes(80, [yesterday, today], {ids: ['small']})), [
    {authIndex: second, value: 70},
]);
context.selectedAccount = first;
assert.deepEqual(plain(context.accountBoxes(80, [yesterday, today], {ids: ['small']})), [
    {authIndex: first, value: 10},
]);
assert.deepEqual(plain(context.accountBoxes(30, [older], null)), []);
context.selectedAccount = '';
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
context.dayOverlay = {day: {modelData: today}};
context.selectedAccount = second;
vm.runInContext(opened[1], context);
assert.equal(context.selectedAccount, '', 'reset the selection when the popout opens');
assert.equal(context.dayOverlay.day, null, 'do not reopen with a stale day overlay');
console.log('PASS: account colours, split availability, filtered usage and family totals, account reset and clamped boxes');

test('label rows stay near their centres without overlapping', () => {
    runFunction('spreadLabels');
    const spread = (centres, height = 120) => plain(context.spreadLabels(centres, 12, height));
    const crowded = spread([10, 12, 14]);
    assert.equal(crowded.length, 3);
    assert.ok(crowded[0] >= 0 && crowded[2] <= 108);
    assert.ok(crowded[1] - crowded[0] >= 12 && crowded[2] - crowded[1] >= 12);
    assert.deepEqual(spread([60]), [54]);
    assert.deepEqual(spread([2, 118]), [0, 108]);
    assert.deepEqual(spread([108, 110, 118]), [84, 96, 108]);
    assert.deepEqual(spread([2, 4, 6], 24), [0, 12, 24]);
    assert.deepEqual(spread([]), []);
});

test('day detail follows the bar order and selected account', () => {
    runFunction('dayDetail');
    context.pillProvider = {accounts: [
        {authIndex: second, label: 'Second label', account: 'Second account'},
        {authIndex: first, account: 'First account'},
    ]};
    context.activity = [older, yesterday, today];
    context.modelFamilies = [
        {family: 'Small', color: '#123456', ids: ['small', 'small-2'], versions: [{name: 'Small 1'}, {name: 'Small 2'}]},
        {family: 'Large', color: '#abcdef', ids: ['large'], versions: [{name: 'Large 1'}]},
        {family: 'Absent', color: '#fedcba', ids: ['absent'], versions: [{name: 'Absent 1'}]},
    ];
    const detail = (entry, height) => plain(context.dayDetail(entry, height));
    assert.deepEqual(detail(today, 100), {
        date: todayDate, total: 200, requests: 9, failed: 2,
        slices: [
            {name: 'Large 1', color: '#abcdef', tokens: 80, y: 0, h: 40},
            {name: 'Small', color: '#123456', tokens: 120, y: 40, h: 60},
        ],
        brackets: [
            {authIndex: second, name: 'Second label', color: '#e6e1e5', tokens: 60, y: 70, h: 30},
            {authIndex: first, name: 'First account', color: '#ff6ec7', tokens: 70, y: 35, h: 35},
        ],
    });

    const oversubscribed = {...today, tokens: {small: 80, large: 20}};
    assert.deepEqual(detail(oversubscribed, 100).brackets.map(({tokens, y, h}) => [tokens, y, h]),
        [[60, 40, 60], [40, 0, 40]]);
    assert.deepEqual(detail({...today, tokens: {small: 99, large: 1}}, 100).slices.map(({y, h}) => [y, h]),
        [[0, 2], [2, 98]], 'a tiny slice remains visible within the mini bar');
    assert.deepEqual(detail(older, 100).brackets, [], 'no brackets on a day without account tokens');

    context.selectedAccount = second;
    assert.deepEqual(detail(today, 120), {
        date: todayDate, total: 60, requests: 3, failed: 1,
        slices: [
            {name: 'Large 1', color: '#abcdef', tokens: 40, y: 0, h: 80},
            {name: 'Small', color: '#123456', tokens: 20, y: 80, h: 40},
        ],
        brackets: [{authIndex: second, name: 'Second label', color: '#e6e1e5', tokens: 60, y: 0, h: 120}],
    });
    assert.deepEqual(detail(older, 120), {
        date: older.date, total: 0, requests: 0, failed: 0, slices: [], brackets: [],
    });
    context.selectedAccount = first;
    assert.deepEqual(detail(oversubscribed, 70).brackets,
        [{authIndex: first, name: 'First account', color: '#ff6ec7', tokens: 40, y: 30, h: 40}],
        'the selected bracket keeps its All clamp but scales to the selected total');
    context.selectedAccount = '';
    context.pillProvider = {accounts: [context.pillProvider.accounts[0]]};
    assert.deepEqual(detail(today, 100).brackets, [], 'no brackets when the account split is hidden');
});

test('day overlay prefers the right and stays within the card margins', () => {
    runFunction('dayOverlayPosition');
    const position = (left, right, top, width = 160) =>
        plain(context.dayOverlayPosition(left, right, top, width, 180, 420, 620, 8, 16));
    assert.deepEqual(position(40, 82, 240), {x: 90, y: 240});
    assert.deepEqual(position(330, 380, 500), {x: 162, y: 440});
    assert.deepEqual(position(180, 232, -15, 260), {x: 16, y: 0});
    assert.deepEqual(position(230, 245, 240), {x: 62, y: 240});
    assert.deepEqual(position(418, 430, 240), {x: 244, y: 240});
});
NODE

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
    const match = source.match(new RegExp(`^    readonly property (?:var|bool|string|int) ${name}: \\{([\\s\\S]*?)\\n    \\}`, 'm'));
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
    {label: 'Today', tokens: 60, requests: 4},
    {label: '7 days', tokens: 110, requests: 6},
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
    {label: 'Today', tokens: 200, requests: 11},
    {label: '7 days', tokens: 330, requests: 18},
], 'All keeps the provider totals, including unattributed usage');

runFunction('familyTokens');
runFunction('familyViewTotal');
const family = {ids: ['small', 'large', 'absent']};
assert.equal(context.familyViewTotal(family), 330, 'All includes unattributed tokens');
context.selectedAccount = second;
assert.equal(context.familyViewTotal(family), 110, 'the selected account contributes only its own tokens');
assert.equal(context.familyViewTotal({ids: ['small']}), 70, 'only models in the family are counted');
context.selectedAccount = '';

const palette = source.match(/readonly property var accountPalette: (\[.*\])/);
assert.ok(palette, 'accountPalette binding is missing');
context.accountPalette = vm.runInContext(palette[1], context);
assert.deepEqual(plain(context.accountPalette), ['#4dd0e1', '#ce93d8', '#fff59d']);
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
assert.equal(cardColor(), '#ce93d8', 'account cards use their palette colour when the split is available');
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

Object.defineProperty(context, 'splitAccounts', {get: () => block('splitAccounts')});

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
console.log('PASS: account colours, split availability, filtered usage and family totals, and account reset');

runFunction('parseModel');
runFunction('modelRows');
runFunction('dayRows');
runFunction('daySegments');
const deployDay = {date: todayDate, requests: 9, failed: 2, tokens: {x: 500, y: 70, z: 8}, accounts: {
    [first]: {requests: 4, failed: 0, tokens: {x: 31, y: 6}},
    [second]: {requests: 3, failed: 1, tokens: {x: 5, z: 1}},
}};
context.pillProvider = {accounts: [
    {authIndex: first, account: 'Account A'},
    {authIndex: second, label: 'Label B', account: 'Account B'},
]};
context.activity = [deployDay];
context.Theme.primary = '#primary';
context.otherColor = '#other';
context.modelFamilies = [
    {family: 'X', color: '#123456', ids: ['x'], versions: [{name: 'X'}]},
    {family: 'Y', color: '#abcdef', ids: ['y'], versions: [{name: 'Y'}]},
];
const groups = detail => plain(detail.groups.map(({key, name, color, tokens, models}) =>
    [key, name, color, tokens, models.map(({name, tokens}) => [name, tokens])]));

test('a split day lists each account with its models, then the unattributed rest', () => {
    const detail = context.dayRows(deployDay);
    assert.deepEqual([detail.date, detail.total, detail.requests, detail.failed], [todayDate, 578, 11, 2]);
    assert.deepEqual(groups(detail), [
        [first, 'Account A', context.accountPalette[0], 37, [['X', 31], ['Y', 6]]],
        [second, 'Label B', context.accountPalette[1], 6, [['X', 5], ['Z', 1]]],
        ['other', 'other', '#other', 535, [['X', 464], ['Y', 64], ['Z', 7]]],
    ]);
    assert.equal(context.dayRows(deployDay).groups[2].models[2].color, '#other', 'a model outside the families gets the neutral colour');
});

test('a selected account shows only its own group and totals', () => {
    context.selectedAccount = second;
    try {
        const detail = context.dayRows(deployDay);
        assert.deepEqual([detail.total, detail.requests, detail.failed], [6, 4, 1]);
        assert.deepEqual(groups(detail), [[second, 'Label B', context.accountPalette[1], 6, [['X', 5], ['Z', 1]]]]);
    } finally {
        context.selectedAccount = '';
    }
});

test('account counts above the provider count are capped, so bar, rows and total agree', () => {
    const day = {...deployDay, accounts: {[first]: {tokens: {x: 699}}, [second]: {tokens: {z: 1}}}};
    const detail = context.dayRows(day);
    assert.deepEqual(groups(detail).map(([key, , , tokens]) => [key, tokens]), [[first, 500], [second, 1], ['other', 77]]);
    assert.equal(detail.groups.reduce((sum, group) => sum + group.tokens, 0), detail.total);
    context.usageHasTokens = true;
    assert.deepEqual(plain(context.daySegments(day)).map(part => part.value), [500, 1, 77]);
});

test('a selected account keeps its own counts even when the provider count is lower', () => {
    const day = {date: todayDate, requests: 2, failed: 0, tokens: {x: 100}, accounts: {
        [first]: {requests: 1, failed: 0, tokens: {x: 100}}, [second]: {requests: 1, failed: 0, tokens: {x: 5}}}};
    context.selectedAccount = second;
    try {
        context.usageHasTokens = true;
        assert.deepEqual(plain(context.daySegments(day)), [{value: 5, color: context.accountPalette[1]}]);
        assert.deepEqual(groups(context.dayRows(day)).map(([key, , , tokens]) => [key, tokens]), [[second, 5]]);
    } finally {
        context.selectedAccount = '';
    }
});

test('a day before the account split is all "other" while the split shows', () => {
    const detail = context.dayRows({...deployDay, accounts: undefined});
    assert.deepEqual(groups(detail), [['other', 'other', '#other', 578, [['X', 500], ['Y', 70], ['Z', 8]]]]);
});

test('without an account split a day is one unnamed group', () => {
    const accounts = context.pillProvider.accounts;
    context.pillProvider = {accounts: [accounts[0]]};
    try {
        assert.deepEqual(groups(context.dayRows(deployDay)), [['day', '', '', 578, [['X', 500], ['Y', 70], ['Z', 8]]]]);
        assert.deepEqual(plain(context.dayRows({date: todayDate, requests: 1, failed: 0, tokens: {}}).groups), []);
    } finally {
        context.pillProvider = {accounts};
    }
});

test('bar heights stay proportional, keep tiny parts visible and fit the plot with gaps', () => {
    runFunction('segmentHeights');
    assert.deepEqual(plain(context.segmentHeights([], 100, 80, 1)), []);
    assert.deepEqual(plain(context.segmentHeights([50], 100, 80, 1)), [40]);
    const tall = context.segmentHeights([99, 1], 100, 80, 1);
    assert.ok(tall[1] >= 2, 'a 1% part stays visible');
    assert.ok(Math.abs(tall[0] + tall[1] + 1 - 80) < 1e-9, 'parts and the gap fill the plot exactly');
    const many = context.segmentHeights([90, 4, 3, 3], 100, 80, 1);
    assert.ok(many.every(h => h >= 2) && many.reduce((a, b) => a + b, 0) + 3 <= 80 + 1e-9);
});

test('the bold quota row is the lowest group, only when there is a choice', () => {
    const provider = context.pillProvider;
    const limiting = groups => { context.pillProvider = {aggregateGroups: groups}; return block('limitingGroup'); };
    assert.equal(limiting([{remainingFraction: 0.82}, {remainingFraction: 0.69}, {remainingFraction: 0.97}]), 1);
    assert.equal(limiting([{remainingFraction: 0.5}, {remainingFraction: 0.5}]), 0);
    assert.equal(limiting([{remainingFraction: 0.4}]), -1);
    assert.equal(limiting([]), -1);
    context.pillProvider = provider;
});

test('the status line says what the numbers are', () => {
    Object.assign(context, {forceFetch: false, quotaProcess: {running: false}, formatAge: iso => iso ? '5m' : ''});
    const status = (quota, lastGood = null) => {
        Object.assign(context, {quota, lastGood, shown: quota && quota.status === 'ok' ? quota : lastGood});
        return block('statusText');
    };
    const good = {status: 'ok', stale: false, updatedAt: 't'};
    assert.equal(status(null), 'Loading…');
    assert.equal(status(good), 'updated 5m');
    assert.equal(status({...good, stale: true}), 'stale · updated 5m');
    assert.equal(status({status: 'unreachable', error: 'proxy unreachable'}, good), 'proxy unreachable · updated 5m');
    assert.equal(status({status: 'no-key', error: 'key unavailable'}), 'key unavailable');
    context.forceFetch = true;
    context.quotaProcess.running = true;
    assert.equal(status(good), 'Refreshing…');
});

test('bars are split by account when possible, otherwise by model family', () => {
    context.usageHasTokens = true;
    assert.deepEqual(plain(context.daySegments(deployDay)), [
        {value: 37, color: context.accountPalette[0]},
        {value: 6, color: context.accountPalette[1]},
        {value: 535, color: '#other'},
    ]);
    context.selectedAccount = first;
    assert.deepEqual(plain(context.daySegments(deployDay)), [{value: 37, color: context.accountPalette[0]}]);
    context.selectedAccount = '';
    context.pillProvider = {accounts: [{authIndex: first}]};
    assert.deepEqual(plain(context.daySegments(deployDay)), [
        {value: 500, color: '#123456'}, {value: 70, color: '#abcdef'},
    ]);
    context.usageHasTokens = false;
    assert.deepEqual(plain(context.daySegments(deployDay)), [{value: 11, color: '#primary'}]);
    assert.deepEqual(plain(context.daySegments({date: todayDate, requests: 0, failed: 0, tokens: {}})), []);
});

test('day overlay centers below the hovered day and clamps to the side margins', () => {
    runFunction('dayOverlayPosition');
    const position = (left, right) =>
        plain(context.dayOverlayPosition(left, right, 240, 260, 180, 420, 620, 8, 16));
    assert.deepEqual(position(134, 184), {x: 29, y: 248});
    assert.deepEqual(position(32, 82), {x: 16, y: 248});
    assert.deepEqual(position(338, 388), {x: 144, y: 248});
});

test('day overlay gives up the gap before overlapping the bars row', () => {
    runFunction('dayOverlayPosition');
    const y = rowBottom => context.dayOverlayPosition(134, 184, rowBottom, 260, 180, 420, 620, 8, 16).y;
    assert.equal(y(436), 440);
    assert.equal(y(440), 440);
    assert.equal(y(441), 440);
    assert.equal(y(-15), 0);
});
NODE

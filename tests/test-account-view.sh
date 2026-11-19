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

runFunction('parseModel');
runFunction('dayDetail');
const deployDay = {date: todayDate, requests: 9, failed: 2, tokens: {x: 500, y: 70, z: 8}, accounts: {
    [first]: {requests: 4, failed: 0, tokens: {x: 31, y: 6}},
    [second]: {requests: 3, failed: 1, tokens: {x: 5, z: 1}},
}};
context.pillProvider = {accounts: [
    {authIndex: first, account: 'Account A'},
    {authIndex: second, label: 'Label B', account: 'Account B'},
]};
context.activity = [deployDay];
context.Theme.surfaceVariantText = '#aabbcc';
context.dayPartGap = 4;
context.familyPalette = ['#123456', '#abcdef', '#fedcba'];
context.modelFamilies = [
    {family: 'X', color: '#123456', ids: ['x', 'x-alt'], versions: [{name: 'X 1'}, {name: 'X 2'}]},
    {family: 'Y', color: '#abcdef', ids: ['y'], versions: [{name: 'Y 1'}]},
    {family: 'Z', color: '#fedcba', ids: ['z'], versions: [{name: 'Z 1'}]},
];
const detail = (entry = deployDay, minHeight = 120) => context.dayDetail(entry, 14, minHeight);
const sliceLabels = part => plain(part.slices.map(({name, tokens}) => [name, tokens]));
function checkLayout({parts, height}) {
    let bottom = 0;
    for (const part of parts) {
        assert.ok(part.y >= bottom, 'parts must not overlap');
        assert.ok(part.h >= Math.max(2, part.slices.length) * 14, 'labels must fit each part');
        bottom = part.y + part.h;
        let sliceBottom = 0;
        for (const slice of part.slices) {
            assert.ok(slice.y >= sliceBottom && slice.h >= 2, 'non-zero slices remain visible without overlap');
            sliceBottom = slice.y + slice.h;
        }
        assert.ok(Math.abs(sliceBottom - part.h) < 1e-9, 'slices fill the part');
    }
    assert.ok(Math.abs(bottom - height) < 1e-9, 'parts and gaps fill the mini bar');
}

test('deploy day groups model slices by account and earlier usage', () => {
    const result = detail();
    assert.ok(Array.isArray(result.parts), 'day detail must return grouped parts');
    const {date, total, requests, failed, height, parts} = result;
    assert.deepEqual([date, total, requests, failed, height], [todayDate, 578, 9, 2, 120]);
    assert.deepEqual(plain(parts.map(({key, name, color, dashed, tokens}) => [key, name, color, dashed, tokens])), [
        ['earlier', 'earlier', '#aabbcc', true, 535],
        [second, 'Label B', '#ff6ec7', false, 6],
        [first, 'Account A', '#e6e1e5', false, 37],
    ]);
    assert.deepEqual(sliceLabels(parts[0]), [['Z 1', 7], ['Y 1', 64], ['X', 464]]);
    assert.deepEqual(sliceLabels(parts[1]), [['Z 1', 1], ['X', 5]]);
    assert.deepEqual(sliceLabels(parts[2]), [['Y 1', 6], ['X', 31]]);
    assert.ok(parts[1].h < parts[2].h, 'equal row counts leave more extra height for the larger account');
    checkLayout(result);
    const grown = detail(deployDay, 80);
    assert.ok(grown.height > 80, 'the bar must grow when labels cannot fit');
    checkLayout(grown);
});

test('a selected account gets the whole mini bar with its own totals', () => {
    context.selectedAccount = second;
    try {
        const {total, requests, failed, parts, height} = detail();
        assert.deepEqual([total, requests, failed], [6, 3, 1]);
        assert.ok(Array.isArray(parts), 'day detail must return grouped parts');
        assert.deepEqual(plain(parts.map(({key, tokens, y, h}) => [key, tokens, y, h])), [[second, 6, 0, 120]]);
        assert.deepEqual(sliceLabels(parts[0]), [['Z 1', 1], ['X', 5]]);
        checkLayout({parts, height});
    } finally {
        context.selectedAccount = '';
    }
});

test('account sums above the day total do not squeeze out any account', () => {
    const result = detail({...deployDay, accounts: {
        [first]: {tokens: {x: 699}}, [second]: {tokens: {z: 1}},
    }});
    assert.ok(Array.isArray(result.parts), 'day detail must return grouped parts');
    assert.deepEqual(plain(result.parts.map(({key, tokens}) => [key, tokens])), [[second, 1], [first, 699]]);
    checkLayout(result);
});

test('a day without an account split has one unnamed part with every used family', () => {
    const result = detail({...deployDay, accounts: undefined, tokens: {x: 577, y: 1}});
    assert.ok(Array.isArray(result.parts), 'day detail must return grouped parts');
    assert.deepEqual(plain(result.parts.map(({key, name, color, dashed}) => [key, name, color, dashed])), [['day', '', '', false]]);
    assert.deepEqual(sliceLabels(result.parts[0]), [['Y 1', 1], ['X', 577]]);
    checkLayout(result);
});

test('an account model missing from all day totals still gets a finite slice', () => {
    const result = detail({...deployDay, accounts: {
        [first]: {tokens: {x: 31, z: 1, w: 2}},
        [second]: {tokens: {x: 5}},
    }, tokens: {x: 508, y: 70}});
    assert.ok(Array.isArray(result.parts), 'day detail must return grouped parts');
    const part = result.parts.find(({key}) => key === first);
    assert.deepEqual(sliceLabels(part), [['W', 2], ['Z 1', 1], ['X', 31]]);
    checkLayout(result);
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

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
    selectedAccount: second, todayDate, tr: key => key === '%1 recorded' ? '%1 recorded' : key, Theme: {}});
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
    {label: 'Today', tokens: 60, requests: 4, missing: false},
    {label: '7 days · 2 recorded', tokens: 110, requests: 6, missing: false, recorded: 2},
], 'usage stats should count only the selected account, over the days it has history');
assert.deepEqual(plain(context.viewEntry(today)), {
    date: todayDate, requests: 3, failed: 1, tokens: {small: 20, large: 40}, missing: false,
});
assert.deepEqual(plain(context.viewEntry(older)), {
    date: older.date, requests: 0, failed: 0, tokens: {}, missing: true,
}, 'a day before the account split is missing for one account, not zero');
context.selectedAccount = 'unknown';
assert.deepEqual(plain(context.viewEntry(today)), {
    date: todayDate, requests: 0, failed: 0, tokens: {}, missing: true,
});
context.selectedAccount = '';
assert.equal(context.viewEntry(today), today);
assert.deepEqual(plain(block('usageStats')), [
    {label: 'Today', tokens: 200, requests: 11, missing: false},
    {label: '7 days', tokens: 330, requests: 18, missing: false, recorded: 3},
], 'All keeps the provider totals, including unattributed usage');
const activityBefore = context.activity;
context.activity = [yesterday, {date: todayDate, requests: 0, failed: 0, tokens: {}, missing: true}];
assert.deepEqual(plain(block('usageStats')).map(({missing, requests, recorded}) => [missing, requests, recorded]), [[true, 0, undefined], [false, 5, 1]],
    'today without history is missing, not a measured zero');
assert.equal(plain(block('usageStats'))[1].label, '7 days · 1 recorded', 'a partial week says how many days it covers');
context.activity = [{date: todayDate, requests: 0, failed: 0, tokens: {}}];
assert.deepEqual(plain(block('usageStats')).map(({missing}) => missing), [false, false], 'a measured zero stays zero');
assert.equal(plain(block('usageStats'))[1].label, '7 days', 'a fully recorded week keeps its plain label');
const noUsage = activity => {
    context.activity = activity;
    context.usageStats = block('usageStats');
    return vm.runInContext(source.match(/^    readonly property bool noUsage: ([\s\S]*?)\n    readonly/m)[1], context);
};
const zeroDay = {date: todayDate, requests: 0, failed: 0, tokens: {}};
const missingDay = {date: '2026-11-18', requests: 0, failed: 0, tokens: {}, missing: true};
assert.equal(noUsage([zeroDay]), true, 'a fully recorded idle week reads as no usage');
assert.equal(noUsage([missingDay, zeroDay]), false, 'a partly recorded idle week keeps its recorded-days summary');
assert.equal(noUsage([missingDay]), true, 'no history at all reads as no data');
delete context.usageStats;
context.activity = activityBefore;

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
assert.deepEqual(plain(context.accountPalette), ['#4dd0e1', '#ce93d8', '#fff59d', '#9fa8da']);
Object.defineProperty(context, 'accountColors', {get: () => block('accountColors')});
Object.defineProperty(context, 'showAccountSplit', {get: () => block('showAccountSplit'), configurable: true});
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

const splitChanged = source.match(/^    onShowAccountSplitChanged: (.+)$/m);
assert.ok(splitChanged, 'the account filter must clear when its chips disappear');
Object.defineProperty(context, 'showAccountSplit', {value: false, configurable: true, writable: true});
context.selectedAccount = second;
vm.runInContext(splitChanged[1], context);
assert.equal(context.selectedAccount, '', 'no hidden filter once the chips are gone');
context.showAccountSplit = true;
context.selectedAccount = second;
vm.runInContext(splitChanged[1], context);
assert.equal(context.selectedAccount, second, 'the filter stays while the chips show');
Object.defineProperty(context, 'showAccountSplit', {get: () => block('showAccountSplit'), configurable: true});

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
        ['other', 'unattributed', '#other', 535, [['X', 464], ['Y', 64], ['Z', 7]]],
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

test('the shared day scale covers account totals when the provider reports fewer tokens', () => {
    runFunction('dayValue');
    context.usageHasTokens = true;
    assert.equal(context.dayValue({tokens: {}, accounts: {[first]: {tokens: {x: 50}}, [second]: {tokens: {x: 20}}}}), 50);
    assert.equal(context.dayValue({tokens: {x: 80}, accounts: {[first]: {tokens: {x: 50}}}}), 80);
    context.usageHasTokens = false;
    assert.equal(context.dayValue({requests: 3, failed: 1, tokens: {}}), 4);
});

test('a day before the account split is all "other" while the split shows', () => {
    const detail = context.dayRows({...deployDay, accounts: undefined});
    assert.deepEqual(groups(detail), [['other', 'unattributed', '#other', 578, [['X', 500], ['Y', 70], ['Z', 8]]]]);
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

test('slivers under 2% of the scale leave the bars but never empty a day', () => {
    runFunction('visibleSegments');
    context.dayMax = 1000;
    const kept = plain(context.visibleSegments([{value: 900, color: 'a'}, {value: 10, color: 'b'}, {value: 90, color: 'c'}]));
    assert.deepEqual(kept.map(part => part.color), ['a', 'c']);
    assert.ok(Math.abs(kept.reduce((sum, part) => sum + part.value, 0) - 1000) < 1e-9, 'the bar keeps the day total height');
    assert.deepEqual(plain(context.visibleSegments([{value: 5, color: 'a'}, {value: 8, color: 'b'}])), [{value: 13, color: 'b'}],
        'a tiny day keeps its largest part at the full day height');
    assert.deepEqual(plain(context.visibleSegments([])), []);
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
    const crowded = context.segmentHeights(Array(28).fill(1), 28, 80, 1);
    assert.ok(crowded.reduce((a, b) => a + b, 0) + 27 <= 80 + 1e-9, '28 parts and their gaps still fit the plot');
});

test('a model only seen in account counts still gets a Models row', () => {
    const activity = context.activity;
    context.activity = [{date: todayDate, requests: 1, failed: 0, tokens: {x: 100}, accounts: {
        [first]: {tokens: {x: 60, w: 7}}, [second]: {tokens: {w: 3}}}}];
    try {
        assert.deepEqual(plain(block('modelTotals')), [{model: 'x', total: 100}, {model: 'w', total: 10}]);
    } finally {
        context.activity = activity;
    }
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
    runFunction('ago');
    const status = (quota, lastGood = null) => {
        Object.assign(context, {quota, lastGood, shown: quota && quota.status === 'ok' ? quota : lastGood,
            dataLive: !!quota && quota.status === 'ok' && !quota.stale});
        return block('statusText');
    };
    const good = {status: 'ok', stale: false, updatedAt: 't'};
    assert.equal(status(null), 'Loading…');
    assert.equal(status(good), 'updated 5m ago');
    assert.equal(status({...good, stale: true}), 'stale · updated 5m ago');
    assert.equal(status({status: 'unreachable', error: 'proxy unreachable'}, good), 'proxy unreachable · updated 5m ago');
    assert.equal(status({status: 'no-key', error: 'key unavailable'}), 'key unavailable');
    const shownBinding = source.match(/^    readonly property var shown: ([\s\S]*?)\n    [a-z]/m)[1];
    const shown = (quota, lastGood) => vm.runInContext(shownBinding, Object.assign(context, {quota, lastGood}));
    const cached = {status: 'ok', source: 'aaaa'};
    assert.equal(shown({status: 'unreachable', source: 'aaaa'}, cached), cached, 'same source keeps its cache');
    assert.equal(shown({status: 'no-key', source: 'bbbb'}, cached), null, 'another source never shows the old cache');
    assert.equal(shown({status: 'script-error'}, cached), cached, 'an unknown source keeps the cache, dimmed');
    assert.equal(shown({status: 'unreachable', source: 'aaaa'}, {status: 'ok'}).status, 'ok', 'a cache from before source ids still counts');
    runFunction('receive');
    const receive = results => {
        Object.assign(context, {quota: null, lastGood: null});
        results.forEach(result => context.receive(result));
        return vm.runInContext(shownBinding, context);
    };
    assert.equal(receive([cached, {status: 'unreachable', source: 'aaaa'}, {status: 'script-error'}]), cached,
        'a timeout after a same-proxy failure keeps the cache');
    assert.equal(receive([cached, {status: 'unreachable', source: 'bbbb'}, {status: 'script-error'}]), null,
        'once another proxy answered, a later timeout cannot bring the old cache back');
    assert.equal(receive([cached, {status: 'no-endpoint', source: ''}]), null, 'no endpoint, no cached proxy data');
    context.forceFetch = true;
    context.quotaProcess.running = true;
    assert.equal(status(good), 'Refreshing…');
    assert.equal(status({status: 'unreachable', error: 'proxy unreachable'}, good), 'Refreshing… · proxy unreachable · updated 5m ago',
        'a refresh keeps the reason the numbers are not live');
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
        plain(context.dayOverlayPosition(left, right, 160, 240, 260, 180, 420, 620, 8, 16));
    assert.deepEqual(position(134, 184), {x: 29, y: 248});
    assert.deepEqual(position(32, 82), {x: 16, y: 248});
    assert.deepEqual(position(338, 388), {x: 144, y: 248});
});

test('day overlay never covers the bars when it fits above them', () => {
    runFunction('dayOverlayPosition');
    const y = (rowTop, rowBottom, height = 180) => context.dayOverlayPosition(134, 184, rowTop, rowBottom, 260, height, 420, 620, 8, 16).y;
    assert.equal(y(352, 432), 440, 'below when it fits');
    assert.equal(y(400, 480), 212, 'above when it does not fit below');
    assert.equal(y(100, 180, 500), 120, 'as low as the popout allows when it fits neither way');
});
NODE

import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "translations.js" as Tr

PluginComponent {
    id: root

    component QuotaRing: Canvas {
        property real fraction: 0
        renderStrategy: Canvas.Cooperative
        onFractionChanged: requestPaint()
        onWidthChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var cx = width / 2, cy = height / 2, r = width * 0.375, lw = width * 0.125;

            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, 2 * Math.PI);
            ctx.lineWidth = lw;
            ctx.strokeStyle = Theme.surfaceVariant;
            ctx.stroke();

            if (fraction > 0) {
                ctx.beginPath();
                ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(fraction, 1));
                ctx.lineWidth = lw;
                ctx.strokeStyle = root.ringColor(fraction);
                ctx.lineCap = "round";
                ctx.stroke();
            }
        }
    }

    component ProviderMark: Item {
        readonly property string iconSource: root.pillProvider ? root.providerIconSource(root.pillProvider.provider) : ""
        width: root.iconSize
        height: root.iconSize

        Image {
            anchors.fill: parent
            visible: parent.iconSource !== ""
            source: parent.iconSource
            sourceSize.width: 2 * root.iconSize
            sourceSize.height: 2 * root.iconSize
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        DankIcon {
            anchors.centerIn: parent
            visible: parent.iconSource === ""
            name: root.pillIcon
            size: root.iconSize
            color: Theme.surfaceVariantText
        }
    }

    component QuotaRow: Column {
        id: quotaRow
        property var group: ({})
        property bool emphasis: false
        readonly property real fraction: Math.max(0, Math.min(1, group.remainingFraction || 0))
        readonly property real overPace: {
            var ws = group.windowSeconds;
            var remainMs = new Date(group.resetTime || "").getTime() - root.nowMs;
            if (!ws || isNaN(remainMs) || remainMs < 0)
                return 0;
            var elapsed = Math.max(0, Math.min(1, 1 - remainMs / (ws * 1000)));
            return Math.round(((1 - fraction) - elapsed) * 100);
        }
        spacing: 4

        Item {
            width: parent.width
            height: rowPercent.implicitHeight

            StyledText {
                anchors.left: parent.left
                anchors.right: rowReset.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: quotaRow.group.label || quotaRow.group.id || ""
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeSmall
                font.weight: quotaRow.emphasis ? Font.DemiBold : Font.Normal
                color: Theme.surfaceText
            }

            StyledText {
                id: rowReset
                anchors.right: rowPercent.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: root.formatCountdown(quotaRow.group.resetTime)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            StyledText {
                id: rowPercent
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(quotaRow.fraction * 100) + "%"
                font.pixelSize: quotaRow.emphasis ? Theme.fontSizeMedium : Theme.fontSizeSmall
                font.weight: quotaRow.emphasis ? Font.Bold : Font.Medium
                font.features: ({ tnum: 1 })
                color: root.ringColor(quotaRow.fraction)
            }
        }

        Rectangle {
            width: parent.width
            height: quotaRow.emphasis ? 8 : 6
            radius: height / 2
            color: Theme.surfaceVariant

            Rectangle {
                width: parent.width * quotaRow.fraction
                height: parent.height
                radius: parent.radius
                color: root.ringColor(quotaRow.fraction)
            }
        }

        StyledText {
            visible: quotaRow.overPace >= 1 && quotaRow.fraction > 0
            text: quotaRow.overPace + "% " + root.tr("over pace")
            font.pixelSize: Theme.fontSizeSmall - 1
            color: Theme.warning
        }
    }

    component DetailLine: Item {
        id: line
        property string name: ""
        property string value: ""
        property color swatch: "transparent"
        property bool showSwatch: false
        property bool roundSwatch: false
        property bool strong: false
        property real indent: 0
        height: lineName.implicitHeight

        Rectangle {
            visible: line.showSwatch
            x: line.indent
            anchors.verticalCenter: parent.verticalCenter
            width: 8
            height: 8
            radius: line.roundSwatch ? 4 : 1
            color: line.swatch
        }

        StyledText {
            id: lineName
            x: line.indent + (line.showSwatch ? 8 + Theme.spacingXS : 0)
            width: Math.max(0, line.width - x - lineValue.implicitWidth - Theme.spacingS)
            text: line.name
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.pixelSize: Theme.fontSizeSmall
            font.weight: line.strong ? Font.Medium : Font.Normal
            color: line.strong ? Theme.surfaceText : Theme.surfaceVariantText
        }

        StyledText {
            id: lineValue
            anchors.right: parent.right
            text: line.value
            font.pixelSize: Theme.fontSizeSmall
            font.features: ({ tnum: 1 })
            font.weight: line.strong ? Font.Medium : Font.Normal
            color: line.strong ? Theme.surfaceText : Theme.surfaceVariantText
        }
    }

    property string lang: (SessionData.locale || Qt.locale().name).split(/[_-]/)[0]
    function tr(key) {
        return Tr.tr(key, lang);
    }

    property string scriptPath: Qt.resolvedUrl("get-quota").toString().replace("file://", "")
    property int refreshInterval: (pluginData.refreshInterval || 2) * 60000
    property bool forceFetch: false

    readonly property var scriptEnvironment: {
        var env = {};
        if (pluginData.vaultCommand !== undefined)
            env.CLIPROXY_QUOTA_VAULT_CMD = pluginData.vaultCommand;
        if (pluginData.endpointOverride)
            env.CLIPROXY_QUOTA_ENDPOINT = pluginData.endpointOverride;
        if (pluginData.literalKey)
            env.CLIPROXY_QUOTA_KEY = pluginData.literalKey;
        return env;
    }

    property var quota: null
    property var lastGood: null
    // pluginData is replaced on every settings save; only a different source counts.
    readonly property string sourceKey: JSON.stringify(scriptEnvironment)
    property bool sourceChanged: false
    onSourceKeyChanged: {
        forceFetch = quota !== null || quotaProcess.running;
        quota = null;
        lastGood = null;
        if (quotaProcess.running)
            sourceChanged = true;
        else
            quotaProcess.running = true;
    }
    readonly property var shown: quota && quota.status === "ok" ? quota
        : lastGood && (!quota?.source || !lastGood.source || quota.source === lastGood.source) ? lastGood : null

    function parseList(raw) {
        var seen = {};
        return String(raw || "").split(",").map(s => s.trim()).filter(s => {
            if (s === "" || seen[s])
                return false;
            seen[s] = true;
            return true;
        });
    }
    readonly property var untrackedProviders: parseList(pluginData.untrackedProviders)
    function isUntracked(provider) {
        return untrackedProviders.indexOf(provider) !== -1;
    }
    function toggleTracking(provider) {
        var list = untrackedProviders.slice();
        var i = list.indexOf(provider);
        if (i === -1)
            list.push(provider);
        else
            list.splice(i, 1);
        pluginService?.savePluginData("cliproxyQuota", "untrackedProviders", list.join(", "));
    }

    readonly property var visibleProviders: shown && shown.providers ? shown.providers : []

    property string focusedProvider: pluginData.focusedProvider || ""
    readonly property int focusedIndex: {
        if (visibleProviders.length === 0)
            return -1;
        for (var i = 0; i < visibleProviders.length; i++) {
            if (visibleProviders[i].provider === focusedProvider)
                return i;
        }
        return 0;
    }
    readonly property var pillProvider: focusedIndex >= 0 ? visibleProviders[focusedIndex] : null
    readonly property real remaining: typeof pillProvider?.aggregate === "number" ? pillProvider.aggregate : -1
    // The group that sets the taskbar number, worth marking only when there is a choice.
    readonly property int limitingGroup: {
        var groups = pillProvider?.aggregateGroups || [];
        var lowest = -1;
        groups.forEach((group, index) => {
            if (lowest < 0 || group.remainingFraction < groups[lowest].remainingFraction)
                lowest = index;
        });
        return groups.length > 1 ? lowest : -1;
    }
    readonly property bool dataLive: quota !== null && quota.status === "ok" && quota.stale !== true
    readonly property var trackedProviders: visibleProviders.filter(p => !isUntracked(p.provider))
    readonly property bool allProblem: trackedProviders.length > 0 && trackedProviders.every(p => p.problem === true)
    readonly property bool drift: quota !== null && quota.drift === true

    property double nowMs: Date.now()

    readonly property string todayDate: Qt.formatDate(new Date(nowMs), "yyyy-MM-dd")

    // The last seven calendar days, oldest first; a day without history is an empty slot.
    readonly property var activity: {
        var byDate = {};
        (pillProvider?.activity || []).forEach(entry => byDate[entry.date] = entry);
        var days = [];
        for (var i = 6; i >= 0; i--) {
            var day = new Date(nowMs);
            day.setHours(12, 0, 0, 0);
            day.setDate(day.getDate() - i);
            var key = Qt.formatDate(day, "yyyy-MM-dd");
            days.push(byDate[key] || { date: key, requests: 0, failed: 0, tokens: {}, missing: true });
        }
        return days;
    }
    readonly property bool hasActivity: (pillProvider?.activity || []).length > 0

    // Fixed hues: stock themes have no tertiary, and account colours must not read as health.
    readonly property var accountPalette: ["#4dd0e1", "#ce93d8", "#fff59d", "#9fa8da"]
    readonly property color otherColor: Theme.outline || "#938f99"

    readonly property var accountColors: {
        var accounts = pillProvider?.accounts || [];
        var colors = {};
        if (accounts.length >= 2) {
            accounts.forEach((account, index) => {
                if (account.authIndex)
                    colors[account.authIndex] = accountPalette[index % accountPalette.length];
            });
        }
        return colors;
    }

    readonly property var splitAccounts: {
        return (pillProvider?.accounts || []).filter(account => accountColors[account.authIndex]);
    }

    readonly property bool showAccountSplit: {
        return Object.keys(accountColors).length >= 2 && activity.some(entry => hasAccountTokens(entry));
    }

    function hasAccountTokens(entry) {
        return Object.values(entry.accounts || {}).some(account => Object.keys(account.tokens || {}).length > 0);
    }

    function cardAccountColor(authIndex) {
        return showAccountSplit ? accountColors[authIndex] || "" : "";
    }

    property string selectedAccount: ""
    readonly property string focusedProviderId: pillProvider?.provider || ""
    onFocusedProviderIdChanged: selectedAccount = ""
    onPillProviderChanged: {
        if (selectedAccount && !pillProvider?.accounts?.some(account => account.authIndex === selectedAccount))
            selectedAccount = "";
    }

    function viewEntry(entry) {
        if (selectedAccount === "")
            return entry;
        var account = entry.accounts?.[selectedAccount];
        return { date: entry.date, requests: account?.requests || 0, failed: account?.failed || 0, tokens: account?.tokens || {},
                 missing: entry.missing === true || !account };
    }

    readonly property var viewActivity: {
        return activity.map(entry => viewEntry(entry));
    }

    function dayTokens(entry) {
        var sum = 0;
        var t = entry.tokens || {};
        for (var m in t)
            sum += t[m];
        return sum;
    }

    readonly property var modelTotals: {
        var sums = {};
        for (var i = 0; i < activity.length; i++) {
            var t = activity[i].tokens || {};
            for (var m in t)
                sums[m] = (sums[m] || 0) + t[m];
        }
        var accountOnly = {};
        activity.forEach(entry => Object.values(entry.accounts || {}).forEach(account => {
            var own = account.tokens || {};
            for (var id in own) {
                if (!(id in sums))
                    accountOnly[id] = (accountOnly[id] || 0) + own[id];
            }
        }));
        Object.assign(sums, accountOnly);
        return Object.keys(sums).filter(m => sums[m] > 0)
            .map(m => ({ model: m, total: sums[m] }))
            .sort((a, b) => b.total - a.total);
    }

    function parseModel(raw) {
        var id = String(raw);
        var prefix = pillProvider ? pillProvider.provider + "-" : "";
        if (prefix !== "-" && id.indexOf(prefix) === 0 && id.length > prefix.length)
            id = id.slice(prefix.length);
        // Vowel-less words read as acronyms and go all caps.
        var cap = s => /^[^aeiouy\d]+$/i.test(s) ? s.toUpperCase() : s.charAt(0).toUpperCase() + s.slice(1);
        var words = [], nums = [], tail = [];
        id.split("-").forEach(t => {
            if (t === "" || /^\d{8}$/.test(t))
                return;
            if (nums.length === 0 && tail.length === 0 && !/^\d/.test(t))
                words.push(cap(t));
            else if (tail.length === 0 && /^\d+$/.test(t))
                nums.push(t);
            else
                tail.push(cap(t));
        });
        if (words.length === 0) {
            // Version first (3-5-name, 2.5-name): the words after it are the family.
            words = tail.filter(t => !/^\d/.test(t));
            tail = tail.filter(t => /^\d/.test(t));
        }
        var version = [nums.join(".")].concat(tail).filter(s => s !== "").join(" ");
        if (words.length === 0)
            return { family: version || String(raw) || "?", name: version || String(raw) || "?" };
        var family = words.concat(tail.filter(t => !/^\d/.test(t))).join(" ");
        var name = [words.join(" "), version].filter(s => s !== "").join(" ");
        return { family: family, name: name };
    }

    readonly property var familyPalette: [1, 0.7, 0.45, 0.25].map(alpha => Theme.withAlpha(Theme.primary, alpha))

    // modelTotals grouped by family, biggest first, one palette colour each.
    readonly property var modelFamilies: {
        var byFamily = {};
        var list = [];
        for (var i = 0; i < modelTotals.length; i++) {
            var mt = modelTotals[i];
            var p = parseModel(mt.model);
            var f = byFamily[p.family];
            if (!f) {
                f = byFamily[p.family] = { family: p.family, total: 0, ids: [], versions: [] };
                list.push(f);
            }
            f.total += mt.total;
            f.ids.push(mt.model);
            var v = f.versions.find(x => x.name === p.name);
            if (v) {
                v.total += mt.total;
                v.ids.push(mt.model);
            } else {
                f.versions.push({ name: p.name, total: mt.total, ids: [mt.model] });
            }
        }
        list.sort((a, b) => b.total - a.total);
        for (var j = 0; j < list.length; j++) {
            list[j].versions.sort((a, b) => b.total - a.total);
            list[j].color = familyPalette[j % familyPalette.length];
        }
        return list;
    }

    function familyTokens(entry, family) {
        var t = entry.tokens || {};
        var sum = 0;
        for (var i = 0; i < family.ids.length; i++)
            sum += t[family.ids[i]] || 0;
        return sum;
    }

    function familyViewTotal(family) {
        return viewActivity.reduce((sum, entry) => sum + familyTokens(entry, family), 0);
    }

    function accountTokens(entry, authIndex, family) {
        var account = entry.accounts?.[authIndex];
        if (!account)
            return 0;
        return family ? familyTokens(account, family) : dayTokens(account);
    }

    function modelRows(tokens) {
        var byName = {};
        var rows = [];
        Object.keys(tokens || {}).forEach(id => {
            if (!(tokens[id] > 0))
                return;
            var model = parseModel(id);
            var row = byName[model.name];
            if (!row) {
                var family = modelFamilies.find(f => f.family === model.family);
                row = byName[model.name] = { name: model.name, tokens: 0, color: family ? family.color : otherColor };
                rows.push(row);
            }
            row.tokens += tokens[id];
        });
        return rows.sort((a, b) => b.tokens - a.tokens);
    }

    // One day as a table: a group per account (or one unnamed group), each with its models.
    // With all accounts shown, each model's account counts are capped at the provider count,
    // so the groups add up to the day total and the unattributed rest is "other".
    function dayRows(allEntry) {
        var entry = viewEntry(allEntry);
        var detail = { date: entry.date, total: dayTokens(entry), requests: entry.requests + entry.failed,
                       failed: entry.failed, missing: entry.missing === true, groups: [] };
        function add(key, name, color, tokens) {
            var models = modelRows(tokens);
            var total = models.reduce((sum, row) => sum + row.tokens, 0);
            if (total > 0)
                detail.groups.push({ key: key, name: name, color: color, tokens: total, models: models });
        }
        if (!showAccountSplit) {
            add("day", "", "", entry.tokens);
            return detail;
        }
        if (selectedAccount) {
            var selected = splitAccounts.find(account => account.authIndex === selectedAccount);
            if (selected)
                add(selected.authIndex, selected.label || selected.account, accountColors[selected.authIndex], entry.tokens);
            return detail;
        }
        var rest = Object.assign({}, allEntry.tokens || {});
        splitAccounts.forEach(account => {
            var own = allEntry.accounts?.[account.authIndex]?.tokens || {};
            var capped = {};
            Object.keys(own).forEach(id => {
                capped[id] = Math.max(0, Math.min(own[id], rest[id] || 0));
                rest[id] = (rest[id] || 0) - capped[id];
            });
            add(account.authIndex, account.label || account.account, accountColors[account.authIndex], capped);
        });
        add("other", tr("other"), otherColor, rest);
        return detail;
    }

    readonly property bool usageHasTokens: modelTotals.length > 0
    function dayValue(entry) {
        if (!usageHasTokens)
            return entry.requests + entry.failed;
        return Object.values(entry.accounts || {}).reduce((max, account) => Math.max(max, dayTokens(account)), dayTokens(entry));
    }
    readonly property real dayMax: activity.reduce((max, entry) => Math.max(max, dayValue(entry)), 0)

    // Bar segments, bottom first: by account when the split exists, otherwise by model family.
    function daySegments(entry) {
        if (!usageHasTokens) {
            var view = viewEntry(entry);
            return view.requests + view.failed > 0 ? [{ value: view.requests + view.failed, color: Theme.primary }] : [];
        }
        if (showAccountSplit)
            return dayRows(entry).groups.map(group => ({ value: group.tokens, color: group.color }));
        var filtered = viewEntry(entry);
        return modelFamilies.map(family => ({ value: familyTokens(filtered, family), color: family.color }))
            .filter(part => part.value > 0);
    }

    // Bar heights in pixels: proportional, at least 2 px each, and with the gaps never above the plot.
    function segmentHeights(values, max, plot, gap) {
        if (values.length === 0 || max <= 0)
            return [];
        var room = Math.max(0, plot - gap * (values.length - 1));
        var heights = values.map(value => Math.max(2, room * value / max));
        var over = heights.reduce((sum, h) => sum + h, 0) - room;
        var shrinkable = heights.reduce((sum, h) => sum + h - 2, 0);
        if (over > 0 && shrinkable > 0)
            heights = heights.map(h => h - (h - 2) * Math.min(1, over / shrinkable));
        var total = heights.reduce((sum, h) => sum + h, 0);
        return total > room ? heights.map(h => h * room / total) : heights;
    }

    function dayOverlayPosition(left, right, rowBottom, width, height, boundsWidth, boundsHeight, gap, inset) {
        var centeredX = (left + right - width) / 2;
        return {
            x: Math.max(inset, Math.min(centeredX, boundsWidth - inset - width)),
            y: Math.max(0, Math.min(rowBottom + gap, boundsHeight - height))
        };
    }

    // Survives the refresh that rebuilds the family delegates.
    property var expandedFamilies: ({})
    function toggleFamily(name) {
        var next = Object.assign({}, expandedFamilies);
        next[name] = !next[name];
        expandedFamilies = next;
    }

    property var expandedAccounts: ({})
    function toggleAccount(key, expanded) {
        var next = Object.assign({}, expandedAccounts);
        next[key] = !expanded;
        expandedAccounts = next;
    }

    readonly property var visibleFamilies: modelFamilies
        .map(family => Object.assign({}, family, { viewTotal: familyViewTotal(family) }))
        .filter(family => family.viewTotal > 0)
        .sort((a, b) => b.viewTotal - a.viewTotal)

    readonly property var usageStats: {
        var today = { label: tr("Today"), tokens: 0, requests: 0, missing: true };
        var week = { label: tr("7 days"), tokens: 0, requests: 0, missing: true };
        for (var i = 0; i < viewActivity.length; i++) {
            var e = viewActivity[i];
            if (e.missing === true)
                continue;
            week.missing = false;
            week.tokens += dayTokens(e);
            week.requests += e.requests + e.failed;
            if (e.date === todayDate) {
                today.missing = false;
                today.tokens = dayTokens(e);
                today.requests = e.requests + e.failed;
            }
        }
        return [today, week];
    }

    function formatTokens(n) {
        if (n >= 1e9)
            return (Math.round(n / 1e8) / 10) + "B";
        if (n >= 1e6)
            return (Math.round(n / 1e5) / 10) + "M";
        if (n >= 1e3)
            return (Math.round(n / 100) / 10) + "k";
        return String(n);
    }

    function formatCount(n) {
        return Number(n).toLocaleString(Qt.locale(), "f", 0);
    }

    function focusPage(index) {
        if (visibleProviders.length === 0)
            return;
        var n = visibleProviders.length;
        var next = ((index % n) + n) % n;
        focusedProvider = visibleProviders[next].provider;
        pluginService?.savePluginData("cliproxyQuota", "focusedProvider", focusedProvider);
    }

    // The provider that took the newest request. A manual focus holds until
    // that changes; then the pill follows it.
    property string activeProvider: pluginData.activeProvider || ""
    function followActiveProvider() {
        var newest = null;
        visibleProviders.forEach(p => {
            if (p.lastRequestEpoch != null && (!newest || p.lastRequestEpoch > newest.lastRequestEpoch))
                newest = p;
        });
        if (!newest || newest.provider === activeProvider)
            return;
        activeProvider = newest.provider;
        focusedProvider = newest.provider;
        pluginService?.savePluginData("cliproxyQuota", "activeProvider", activeProvider);
        pluginService?.savePluginData("cliproxyQuota", "focusedProvider", focusedProvider);
    }

    function providerIconSource(name) {
        var iconAssets = { "claude": 1, "codex": 1, "github-copilot": 1 };
        return iconAssets[name] ? Qt.resolvedUrl("assets/" + name + ".svg") : "";
    }

    function providerIcon(name) {
        var icons = {};
        icons["claude"] = "neurology";
        icons["codex"] = "terminal";
        icons["github-copilot"] = "code";
        icons["gemini"] = "auto_awesome";
        icons["kimi"] = "chat";
        icons["xai"] = "rocket_launch";
        return icons[name] || "cloud";
    }

    function ago(iso) {
        var age = formatAge(iso);
        return age === "" || age === tr("just now") ? age : tr("%1 ago").replace("%1", age);
    }

    function formatAge(iso) {
        if (!iso)
            return "";
        var t = new Date(iso).getTime();
        if (isNaN(t))
            return "";
        var elapsed = nowMs - t;
        if (elapsed < 60000)
            return tr("just now");
        var mins = Math.floor(elapsed / 60000);
        if (mins < 60)
            return mins + "m";
        var hours = Math.floor(mins / 60);
        if (hours < 24)
            return hours + "h";
        return Math.floor(hours / 24) + "d";
    }

    function formatCountdown(iso) {
        if (!iso)
            return "";
        var t = new Date(iso).getTime();
        if (isNaN(t))
            return "";
        var remainingMs = t - nowMs;
        if (remainingMs <= 0)
            return tr("resets soon");
        var mins = Math.ceil(remainingMs / 60000);
        var days = Math.floor(mins / 1440);
        var hours = Math.floor((mins % 1440) / 60);
        var m = mins % 60;
        var span = days > 0 ? days + "d " + hours + "h"
                 : hours > 0 ? hours + "h " + m + "m"
                 : m + "m";
        return tr("resets in") + " " + span;
    }

    property bool receivedThisRun: false

    function ringColor(fraction) {
        if (fraction >= 0.7)
            return Theme.success || "#4caf50";
        if (fraction >= 0.3)
            return Theme.warning || "#ff9800";
        return Theme.error || "#f44336";
    }

    function pillText(sign) {
        if (quota === null)
            return "…";
        var mark = dataLive ? "" : "?";
        return remaining < 0 ? (pillProvider ? "\u2014" : "") + mark : Math.round(remaining * 100) + sign + mark;
    }

    readonly property string pillIcon: quota === null ? "hourglass_empty"
        : pillProvider ? providerIcon(pillProvider.provider) : "cloud_off"

    readonly property string statusText: {
        if (quota === null)
            return tr("Loading…");
        if (forceFetch && quotaProcess.running)
            return tr("Refreshing…");
        var age = ago(shown ? shown.updatedAt : "");
        if (quota.status !== "ok")
            return (quota.error || tr("no data")) + (lastGood && age ? " · " + tr("updated") + " " + age : "");
        if (quota.stale)
            return tr("stale") + (age ? " · " + tr("updated") + " " + age : "");
        return age ? tr("updated") + " " + age : "";
    }
    readonly property bool needsSettings: quota !== null && (quota.status === "no-key" || quota.status === "no-endpoint")
    readonly property color statusColor: quota && quota.status !== "ok" ? Theme.error
        : quota && quota.stale ? Theme.warning : Theme.surfaceVariantText

    Process {
        id: quotaProcess
        command: ["timeout", "60", "bash", root.scriptPath].concat(root.forceFetch ? ["--force"] : [])
        environment: root.scriptEnvironment
        running: false

        stdout: SplitParser {
            onRead: data => {
                var line = data.trim();
                if (line === "" || root.sourceChanged)
                    return;
                try {
                    root.quota = JSON.parse(line);
                    if (root.quota.status === "ok")
                        root.lastGood = root.quota;
                    root.receivedThisRun = true;
                } catch (e) {
                }
                root.followActiveProvider();
            }
        }

        onRunningChanged: {
            if (running)
                root.receivedThisRun = false;
        }

        onExited: (exitCode, exitStatus) => {
            if (root.sourceChanged) {
                root.sourceChanged = false;
                Qt.callLater(() => quotaProcess.running = true);
                return;
            }
            if (exitCode !== 0 || !root.receivedThisRun)
                root.quota = ({ status: "script-error", error: "fetch failed", stale: true, providers: [] });
            root.forceFetch = root.forceFetch && root.quota.status !== "ok";
        }
    }

    Timer {
        interval: root.refreshInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!quotaProcess.running)
                quotaProcess.running = true;
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            opacity: root.dataLive ? 1 : 0.6

            ProviderMark {
                anchors.verticalCenter: parent.verticalCenter
            }

            QuotaRing {
                width: root.iconSize
                height: root.iconSize
                visible: root.remaining >= 0
                fraction: root.remaining
                anchors.verticalCenter: parent.verticalCenter
            }


            StyledText {
                text: root.pillText("%")
                visible: text !== ""
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            DankIcon {
                name: "warning"
                visible: root.allProblem
                size: root.iconSize
                color: Theme.warning
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            opacity: root.dataLive ? 1 : 0.6

            ProviderMark {
                anchors.horizontalCenter: parent.horizontalCenter
            }

            QuotaRing {
                width: root.iconSize
                height: root.iconSize
                visible: root.remaining >= 0
                fraction: root.remaining
                anchors.horizontalCenter: parent.horizontalCenter
            }


            StyledText {
                text: root.pillText("")
                visible: text !== ""
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }

            DankIcon {
                name: "warning"
                visible: root.allProblem
                size: root.iconSize
                color: Theme.warning
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutWidth: 420
    readonly property int basePopoutHeight: 620
    popoutHeight: basePopoutHeight

    popoutContent: Component {
        FocusScope {
            id: popoutRoot
            implicitWidth: root.popoutWidth
            implicitHeight: root.popoutHeight
            focus: true

            property var parentPopout: null

            readonly property real headerHeight: activityScroll.y

            // Grow with the content, from the base height up to 1.5x, then scroll.
            Binding {
                target: root
                property: "popoutHeight"
                value: Math.round(Math.min(root.basePopoutHeight * 1.5,
                                           Math.max(root.focusedIndex >= 0 ? root.basePopoutHeight : 0,
                                                    popoutRoot.headerHeight + accountsColumn.height + Theme.spacingL)))
            }
            Connections {
                target: popoutRoot.parentPopout
                function onOpened() {
                    root.selectedAccount = "";
                    dayOverlay.day = null;
                    Qt.callLater(() => popoutRoot.forceActiveFocus());
                }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Left) {
                    root.focusPage(root.focusedIndex - 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right) {
                    root.focusPage(root.focusedIndex + 1);
                    event.accepted = true;
                }
            }

            Timer {
                interval: 30000
                running: popoutRoot.visible
                repeat: true
                triggeredOnStart: true
                onTriggered: root.nowMs = Date.now()
            }

            Column {
                id: popoutColumn
                width: parent.width
                spacing: Theme.spacingS

                Item {
                    width: parent.width
                    height: Math.max(40, statusLine.implicitHeight + Theme.spacingS)

                    StyledText {
                        id: statusLine
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: headerActions.left
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.focusedIndex >= 0
                        text: root.statusText
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.pixelSize: Theme.fontSizeSmall
                        color: root.statusColor
                    }

                    Row {
                        id: headerActions
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        DankActionButton {
                            readonly property bool untracked: root.pillProvider !== null && root.isUntracked(root.pillProvider.provider)
                            visible: root.pillProvider !== null
                            buttonSize: 32
                            iconName: untracked ? "notifications_off" : "notifications"
                            iconColor: untracked ? Theme.surfaceVariantText : Theme.surfaceText
                            tooltipText: root.pillProvider ? root.tr("Taskbar warnings") + " \u00b7 " + root.pillProvider.provider
                                                             + ": " + (untracked ? root.tr("off") : root.tr("on")) : ""
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: if (root.pillProvider) root.toggleTracking(root.pillProvider.provider)
                        }

                        DankActionButton {
                            iconName: "refresh"
                            buttonSize: 32
                            tooltipText: root.tr("Refresh")
                            enabled: !quotaProcess.running
                            iconColor: quotaProcess.running ? Theme.surfaceVariantText : Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                                root.forceFetch = true;
                                if (!quotaProcess.running)
                                    quotaProcess.running = true;
                            }
                        }
                    }
                }

                Item {
                    id: navTabs
                    width: parent.width
                    height: 44
                    visible: root.focusedIndex >= 0
                    opacity: root.dataLive ? 1 : 0.6

                    Flickable {
                        id: providerScroll
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        contentWidth: Math.max(width, providerRow.width)
                        contentHeight: height
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true

                        function revealFocused() {
                            var tab = providerTabs.itemAt(root.focusedIndex);
                            if (!tab) return;
                            var left = providerRow.x + tab.x;
                            var right = left + tab.width;
                            contentX = Math.max(0, Math.min(contentWidth - width,
                                left < contentX ? left : right > contentX + width ? right - width : contentX));
                        }
                        onWidthChanged: Qt.callLater(revealFocused)
                        Connections {
                            target: root
                            function onFocusedIndexChanged() { Qt.callLater(providerScroll.revealFocused); }
                        }

                    Row {
                        id: providerRow
                        x: Math.max(0, (providerScroll.width - width) / 2)
                        anchors.verticalCenter: parent.verticalCenter
                        onWidthChanged: Qt.callLater(providerScroll.revealFocused)
                        spacing: Theme.spacingS

                        Repeater {
                            id: providerTabs
                            model: root.visibleProviders

                            delegate: StyledRect {
                                id: providerTab
                                required property var modelData
                                required property int index
                                readonly property bool focused: index === root.focusedIndex
                                readonly property string iconSource: root.providerIconSource(modelData.provider)
                                readonly property bool genericIcon: iconSource === "" && root.providerIcon(modelData.provider) === "cloud"

                                height: 36
                                width: tabContent.width + 2 * Theme.spacingM
                                radius: height / 2
                                color: focused ? Theme.withAlpha(Theme.primary, 0.16) : Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                                border.width: 1
                                border.color: focused ? Theme.withAlpha(Theme.primary, 0.45) : Theme.outlineLight

                                Row {
                                    id: tabContent
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS

                                    Item {
                                        width: 20
                                        height: 20
                                        anchors.verticalCenter: parent.verticalCenter
                                        opacity: providerTab.focused ? 1 : 0.7

                                        Image {
                                            anchors.fill: parent
                                            visible: providerTab.iconSource !== ""
                                            source: providerTab.iconSource
                                            sourceSize.width: 40
                                            sourceSize.height: 40
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                        }

                                        DankIcon {
                                            anchors.centerIn: parent
                                            visible: providerTab.iconSource === ""
                                            name: root.providerIcon(providerTab.modelData.provider)
                                            size: 18
                                            color: providerTab.focused ? Theme.primary : Theme.surfaceVariantText
                                        }
                                    }

                                    StyledText {
                                        visible: providerTab.focused || providerTab.genericIcon
                                        text: providerTab.modelData.provider
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: providerTab.focused ? Theme.surfaceText : Theme.surfaceVariantText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    StyledText {
                                        readonly property bool known: typeof providerTab.modelData.aggregate === "number"
                                        text: known ? Math.round(providerTab.modelData.aggregate * 100) + "%" : "\u2014"
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        font.features: ({ tnum: 1 })
                                        color: root.dataLive && known ? root.ringColor(providerTab.modelData.aggregate) : Theme.surfaceVariantText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.focusPage(providerTab.index)
                                }

                                Rectangle {
                                    visible: providerTab.modelData.problem === true && !root.isUntracked(providerTab.modelData.provider)
                                    width: 9
                                    height: 9
                                    radius: 4.5
                                    color: Theme.error
                                    border.width: 1
                                    border.color: Theme.surfaceContainerHigh
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.topMargin: -1
                                    anchors.rightMargin: -1
                                }
                            }
                        }
                    }
                    }
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 2 * Theme.spacingM
                    visible: root.focusedIndex >= 0 && root.needsSettings
                    text: root.tr("Check the plugin settings or unlock your vault.")
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 2 * Theme.spacingM
                    visible: root.drift
                    text: root.tr("The server sends a newer data format. Update this widget.")
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.info
                }

                DankFlickable {
                    id: activityScroll
                    width: parent.width
                    height: Math.max(0, root.popoutHeight - popoutRoot.headerHeight)
                    contentHeight: accountsColumn.height
                    clip: true
                    opacity: root.dataLive || root.focusedIndex < 0 ? 1 : 0.6

                    Column {
                        id: accountsColumn
                        width: parent.width
                        spacing: Theme.spacingS

                        Column {
                            visible: root.focusedIndex < 0
                            width: parent.width - 2 * Theme.spacingM
                            anchors.horizontalCenter: parent.horizontalCenter
                            topPadding: Theme.spacingL
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width
                                text: root.quota === null ? root.tr("Loading…") : root.quota.error || root.tr("no data")
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                font.pixelSize: Theme.fontSizeMedium
                                color: root.quota && root.quota.status !== "ok" ? Theme.error : Theme.surfaceVariantText
                            }

                            StyledText {
                                width: parent.width
                                visible: root.needsSettings
                                text: root.tr("Check the plugin settings or unlock your vault.")
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }

                        StyledRect {
                            id: quotaCard
                            visible: root.pillProvider !== null
                            width: accountsColumn.width - 2 * Theme.spacingM
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: quotaContent.height + 2 * Theme.spacingM
                            radius: Theme.cornerRadius
                            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

                            Column {
                                id: quotaContent
                                anchors.centerIn: parent
                                width: parent.width - 2 * Theme.spacingM
                                spacing: Theme.spacingM

                                StyledText {
                                    text: root.tr("Quota remaining")
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                }

                                StyledText {
                                    visible: root.pillProvider !== null && (root.pillProvider.aggregateGroups || []).length === 0
                                    text: root.pillProvider && root.pillProvider.problem === true
                                          ? root.tr("no account is serving") : root.tr("no quota reported")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }

                                Repeater {
                                    model: root.pillProvider ? (root.pillProvider.aggregateGroups || []) : []

                                    delegate: QuotaRow {
                                        required property var modelData
                                        required property int index
                                        width: quotaContent.width
                                        group: modelData
                                        emphasis: index === root.limitingGroup
                                    }
                                }
                            }
                        }

                        StyledText {
                            visible: root.pillProvider !== null && root.pillProvider.accounts.length > 0
                            x: Theme.spacingM
                            topPadding: Theme.spacingS
                            text: root.tr("Accounts")
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: Theme.surfaceVariantText
                        }

                        Repeater {
                            model: root.pillProvider ? root.pillProvider.accounts : []

                            delegate: StyledRect {
                                id: accountCard
                                required property var modelData

                                readonly property bool healthy: !modelData.disabled && !modelData.unavailable
                                                                && (modelData.status === "active" || modelData.supported === false)
                                readonly property var accountColor: root.cardAccountColor(modelData.authIndex)
                                readonly property string expandKey: modelData.authIndex || modelData.account
                                readonly property bool expanded: root.expandedAccounts[expandKey] ?? !!modelData.error
                                readonly property real worst: modelData.groups.reduce((min, group) => Math.min(min, group.remainingFraction), 2)

                                width: accountsColumn.width - 2 * Theme.spacingM
                                anchors.horizontalCenter: parent.horizontalCenter
                                height: accountHeader.height + (expanded ? accountBody.height + Theme.spacingS : 0)
                                radius: Theme.cornerRadius
                                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                                border.width: healthy ? 0 : 1
                                border.color: Theme.withAlpha(Theme.error, 0.5)
                                clip: true

                                Behavior on height {
                                    NumberAnimation {
                                        duration: Theme.shortDuration
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                Item {
                                    id: accountHeader
                                    width: parent.width
                                    height: 44
                                    activeFocusOnTab: true
                                    Accessible.role: Accessible.Button
                                    Accessible.name: accountCard.modelData.label || accountCard.modelData.account
                                    Accessible.onPressAction: root.toggleAccount(accountCard.expandKey, accountCard.expanded)
                                    Keys.onSpacePressed: root.toggleAccount(accountCard.expandKey, accountCard.expanded)
                                    Keys.onReturnPressed: root.toggleAccount(accountCard.expandKey, accountCard.expanded)
                                    Keys.onEnterPressed: root.toggleAccount(accountCard.expandKey, accountCard.expanded)
                                    onActiveFocusChanged: {
                                        if (activeFocus)
                                            activityScroll.contentY = Math.max(accountCard.y + height - activityScroll.height,
                                                                               Math.min(accountCard.y, activityScroll.contentY));
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        radius: Theme.cornerRadius
                                        visible: accountHeader.activeFocus
                                        color: "transparent"
                                        border.width: 2
                                        border.color: Theme.primary
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleAccount(accountCard.expandKey, accountCard.expanded)
                                    }

                                    Rectangle {
                                        visible: accountCard.accountColor !== ""
                                        x: 5
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 4
                                        height: 22
                                        radius: 2
                                        color: accountCard.accountColor || "transparent"
                                    }

                                    Rectangle {
                                        id: healthDot
                                        anchors.left: parent.left
                                        anchors.leftMargin: Theme.spacingM
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 8
                                        height: 8
                                        radius: 4
                                        color: accountCard.modelData.disabled || accountCard.modelData.unavailable
                                               || accountCard.modelData.supported === false
                                               ? Theme.surfaceVariantText
                                               : accountCard.modelData.status !== "active" ? Theme.error : Theme.success
                                    }

                                    StyledText {
                                        anchors.left: healthDot.right
                                        anchors.leftMargin: Theme.spacingS
                                        anchors.right: accountTags.left
                                        anchors.rightMargin: Theme.spacingS
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: accountCard.modelData.label || accountCard.modelData.account
                                        elide: Text.ElideRight
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: Theme.surfaceText
                                    }

                                    Row {
                                        id: accountTags
                                        anchors.right: accountWorst.left
                                        anchors.rightMargin: Theme.spacingS
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.spacingS

                                        StyledText {
                                            visible: accountCard.modelData.headline && root.pillProvider.accounts.length > 1
                                            text: root.tr("shown above")
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.primary
                                        }

                                        StyledText {
                                            visible: accountCard.modelData.supported !== false && accountCard.modelData.status !== "active"
                                                     && !accountCard.modelData.disabled && !accountCard.modelData.unavailable
                                            text: accountCard.modelData.status
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.error
                                        }

                                        StyledText {
                                            visible: accountCard.modelData.disabled
                                            text: root.tr("disabled")
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.error
                                        }

                                        StyledText {
                                            visible: accountCard.modelData.unavailable
                                            text: root.tr("unavailable")
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.warning
                                        }

                                        StyledText {
                                            visible: accountCard.modelData.supported === false
                                            text: root.tr("unsupported")
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                        }
                                    }

                                    StyledText {
                                        id: accountWorst
                                        anchors.right: accountChevron.left
                                        anchors.rightMargin: Theme.spacingXS
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: accountCard.worst <= 1 ? Math.round(Math.max(0, accountCard.worst) * 100) + "%" : ""
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Medium
                                        font.features: ({ tnum: 1 })
                                        color: root.ringColor(accountCard.worst)
                                    }

                                    DankIcon {
                                        id: accountChevron
                                        anchors.right: parent.right
                                        anchors.rightMargin: Theme.spacingM
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: accountCard.expanded ? "expand_less" : "expand_more"
                                        size: 18
                                        color: Theme.surfaceVariantText
                                    }
                                }

                                Column {
                                    id: accountBody
                                    anchors.top: accountHeader.bottom
                                    width: parent.width - 2 * Theme.spacingM
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: Theme.spacingS
                                    visible: accountCard.expanded

                                    StyledText {
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        text: [
                                            accountCard.modelData.status !== "active" && (accountCard.modelData.disabled || accountCard.modelData.unavailable
                                                || accountCard.modelData.supported === false) ? accountCard.modelData.status : "",
                                            accountCard.modelData.lastRequestAt ? root.tr("last request") + " " + root.ago(accountCard.modelData.lastRequestAt) : "",
                                            root.formatCount(accountCard.modelData.success || 0) + " " + root.tr("ok"),
                                            root.formatCount(accountCard.modelData.failed || 0) + " " + root.tr("failed")
                                        ].filter(part => part !== "").join(" \u00b7 ")
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                    }

                                    StyledText {
                                        visible: accountCard.modelData.error !== ""
                                        width: parent.width
                                        text: accountCard.modelData.error
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: accountCard.healthy ? Theme.surfaceVariantText : Theme.error
                                        wrapMode: Text.WordWrap
                                    }

                                    StyledText {
                                        visible: accountCard.modelData.noQuota
                                        text: root.tr("no quota reported")
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                    }

                                    Repeater {
                                        model: accountCard.modelData.headline ? [] : accountCard.modelData.groups

                                        delegate: QuotaRow {
                                            required property var modelData
                                            width: accountBody.width
                                            group: modelData
                                        }
                                    }
                                }
                            }
                        }

                        StyledText {
                            visible: activityCard.visible
                            x: Theme.spacingM
                            topPadding: Theme.spacingS
                            text: root.tr("Usage")
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: Theme.surfaceVariantText
                        }

                        Flickable {
                            id: accountScroll
                            visible: root.showAccountSplit
                            width: accountsColumn.width - 2 * Theme.spacingM
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: 32
                            contentWidth: Math.max(width, accountChips.width)
                            contentHeight: height
                            flickableDirection: Flickable.HorizontalFlick
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true

                            Row {
                                id: accountChips
                                spacing: Theme.spacingS

                                Repeater {
                                    model: root.showAccountSplit ? [{ authIndex: "", label: root.tr("All accounts") }].concat(root.splitAccounts) : []

                                    delegate: StyledRect {
                                        id: accountChip
                                        required property var modelData
                                        readonly property bool selected: modelData.authIndex === root.selectedAccount
                                        readonly property string chipLabel: modelData.label || modelData.account
                                        height: accountScroll.height
                                        width: chipContent.width + 2 * Theme.spacingS
                                        radius: height / 2
                                        color: selected ? Theme.withAlpha(Theme.primary, 0.16) : Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                                        border.width: activeFocus ? 2 : 1
                                        border.color: activeFocus ? Theme.primary : selected ? Theme.withAlpha(Theme.primary, 0.45) : Theme.outlineLight
                                        activeFocusOnTab: true
                                        Accessible.role: Accessible.RadioButton
                                        Accessible.name: chipLabel
                                        Accessible.checkable: true
                                        Accessible.checked: selected
                                        Accessible.onPressAction: root.selectedAccount = modelData.authIndex
                                        Keys.onSpacePressed: root.selectedAccount = modelData.authIndex
                                        Keys.onReturnPressed: root.selectedAccount = modelData.authIndex
                                        Keys.onEnterPressed: root.selectedAccount = modelData.authIndex
                                        onActiveFocusChanged: {
                                            if (activeFocus)
                                                accountScroll.contentX = Math.max(x + width - accountScroll.width, Math.min(x, accountScroll.contentX));
                                        }

                                        Row {
                                            id: chipContent
                                            anchors.centerIn: parent
                                            spacing: Theme.spacingXS

                                            Rectangle {
                                                visible: accountChip.modelData.authIndex !== ""
                                                width: 8
                                                height: width
                                                radius: width / 2
                                                color: root.accountColors[accountChip.modelData.authIndex] || "transparent"
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            StyledText {
                                                text: accountChip.chipLabel
                                                elide: Text.ElideRight
                                                width: Math.min(implicitWidth, 160)
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceText
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.selectedAccount = accountChip.modelData.authIndex
                                        }
                                    }
                                }
                            }
                        }

                        StyledRect {
                            id: activityCard
                            visible: root.hasActivity
                            width: accountsColumn.width - 2 * Theme.spacingM
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: activityContent.height + 2 * Theme.spacingM
                            radius: Theme.cornerRadius
                            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

                            Column {
                                id: activityContent
                                anchors.centerIn: parent
                                width: parent.width - 2 * Theme.spacingM
                                spacing: Theme.spacingS

                                StyledText {
                                    text: root.usageHasTokens ? root.tr("Tokens per day") : root.tr("Requests per day")
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                }

                                Repeater {
                                    model: root.usageStats

                                    delegate: DetailLine {
                                        required property var modelData
                                        width: activityContent.width
                                        name: modelData.label
                                        value: modelData.missing ? root.tr("no data")
                                               : (root.usageHasTokens ? root.formatTokens(modelData.tokens) + " " + root.tr("tokens") + " \u00b7 " : "")
                                                 + root.formatCount(modelData.requests) + " " + root.tr("requests")
                                    }
                                }

                                Row {
                                    id: barsRow
                                    visible: root.dayMax > 0
                                    width: parent.width
                                    topPadding: Theme.spacingXS

                                    Repeater {
                                        model: root.activity

                                        delegate: Column {
                                            id: dayColumn
                                            required property var modelData
                                            readonly property var segments: root.daySegments(modelData)
                                            readonly property var bars: {
                                                var heights = root.segmentHeights(segments.map(part => part.value), root.dayMax, 80, 1);
                                                return segments.map((part, i) => ({ color: part.color, h: heights[i] })).reverse();
                                            }
                                            readonly property bool isToday: modelData.date === root.todayDate
                                            readonly property real barWidth: Math.min(28, width - Theme.spacingS)
                                            width: barsRow.width / root.activity.length
                                            spacing: 4

                                            Item {
                                                width: parent.width
                                                height: 80

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: 4
                                                    visible: dayOverlay.day === dayColumn
                                                    color: Theme.withAlpha(Theme.surfaceText, 0.08)
                                                }

                                                Rectangle {
                                                    visible: dayColumn.segments.length === 0
                                                    anchors.bottom: parent.bottom
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    width: dayColumn.barWidth
                                                    height: 2
                                                    color: Theme.surfaceVariant
                                                }

                                                Item {
                                                    anchors.fill: parent
                                                    clip: true

                                                    Column {
                                                        anchors.bottom: parent.bottom
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        spacing: 1

                                                        Repeater {
                                                            model: dayColumn.bars

                                                            delegate: Rectangle {
                                                                required property var modelData
                                                                width: dayColumn.barWidth
                                                                height: modelData.h
                                                                color: modelData.color
                                                            }
                                                        }
                                                    }
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    acceptedButtons: Qt.NoButton
                                                    onEntered: dayOverlay.day = dayColumn
                                                    onExited: {
                                                        if (dayOverlay.day === dayColumn)
                                                            dayOverlay.day = null;
                                                    }
                                                }
                                            }

                                            StyledText {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: {
                                                    var d = new Date(dayColumn.modelData.date + "T00:00:00");
                                                    return isNaN(d.getTime()) ? "" : d.toLocaleDateString(Qt.locale(), "ddd");
                                                }
                                                font.pixelSize: Theme.fontSizeSmall - 1
                                                font.weight: dayColumn.isToday ? Font.Bold : Font.Normal
                                                color: dayColumn.isToday ? Theme.surfaceText : Theme.surfaceVariantText
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        StyledRect {
                            id: modelsCard
                            visible: root.visibleFamilies.length > 0
                            width: accountsColumn.width - 2 * Theme.spacingM
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: modelsContent.height + 2 * Theme.spacingM
                            radius: Theme.cornerRadius
                            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

                            Column {
                                id: modelsContent
                                anchors.centerIn: parent
                                width: parent.width - 2 * Theme.spacingM
                                spacing: Theme.spacingS

                                StyledText {
                                    text: root.tr("Models") + " \u00b7 " + root.tr("7 days")
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                }

                                Repeater {
                                    model: root.visibleFamilies

                                    delegate: Column {
                                        id: familyRow
                                        required property var modelData
                                        readonly property bool multi: modelData.versions.length > 1
                                        readonly property bool expanded: multi && root.expandedFamilies[modelData.family] === true
                                        width: modelsContent.width
                                        spacing: 4

                                        Item {
                                            width: parent.width
                                            height: familyLine.height

                                            DetailLine {
                                                id: familyLine
                                                anchors.left: parent.left
                                                anchors.right: familyChevron.left
                                                name: familyRow.multi ? familyRow.modelData.family : familyRow.modelData.versions[0].name
                                                value: root.formatTokens(familyRow.modelData.viewTotal)
                                                strong: true
                                            }

                                            DankIcon {
                                                id: familyChevron
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                opacity: familyRow.multi ? 1 : 0
                                                name: familyRow.expanded ? "expand_less" : "expand_more"
                                                size: 16
                                                color: Theme.surfaceVariantText
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                anchors.margins: -2
                                                enabled: familyRow.multi
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.toggleFamily(familyRow.modelData.family)
                                            }
                                        }

                                        Rectangle {
                                            width: parent.width
                                            height: 6
                                            radius: 3
                                            color: Theme.surfaceVariant

                                            Rectangle {
                                                width: parent.width * Math.min(1, familyRow.modelData.viewTotal / root.modelFamilies[0].total)
                                                height: parent.height
                                                radius: parent.radius
                                                color: familyRow.modelData.color
                                            }
                                        }

                                        Column {
                                            visible: familyRow.expanded
                                            width: parent.width
                                            topPadding: 2
                                            spacing: 4

                                            Repeater {
                                                model: familyRow.expanded
                                                       ? familyRow.modelData.versions
                                                             .map(version => ({ name: version.name, total: root.familyViewTotal(version) }))
                                                             .filter(version => version.total > 0)
                                                             .sort((a, b) => b.total - a.total) : []

                                                delegate: DetailLine {
                                                    required property var modelData
                                                    width: modelsContent.width - familyChevron.width
                                                    indent: Theme.spacingM
                                                    name: modelData.name
                                                    value: root.formatTokens(modelData.total)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        StyledText {
                            width: accountsColumn.width - 2 * Theme.spacingM
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: root.shown !== null && (root.shown.unsupportedProviders || []).length > 0
                            text: visible ? root.tr("unsupported") + ": " + root.shown.unsupportedProviders.join(", ") : ""
                            wrapMode: Text.WordWrap
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }
            }

            StyledRect {
                id: dayOverlay
                property Item day: null
                readonly property var detail: day ? root.dayRows(day.modelData) : null
                readonly property var position: {
                    if (!day)
                        return { x: 0, y: 0 };
                    var left = day.mapToItem(popoutRoot, 0, 0).x;
                    var rowBottom = popoutColumn.y + activityScroll.y - activityScroll.contentY
                        + accountsColumn.y + activityCard.y + activityContent.y + barsRow.y + barsRow.height;
                    return root.dayOverlayPosition(left, left + day.width, rowBottom, width, height,
                                                   popoutRoot.width, popoutRoot.height, Theme.spacingS, Theme.spacingM);
                }

                z: 10
                visible: !!day && day.visible
                opacity: root.dataLive ? 1 : 0.6
                x: position.x
                y: position.y
                width: Math.min(popoutRoot.width - 2 * Theme.spacingM, 280)
                height: dayContents.height + 2 * Theme.spacingS
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHighest ?? Theme.surfaceContainerHigh
                border.width: 1
                border.color: Theme.outline

                Column {
                    id: dayContents
                    x: Theme.spacingS
                    y: Theme.spacingS
                    width: parent.width - 2 * Theme.spacingS
                    spacing: Theme.spacingXS

                    DetailLine {
                        width: parent.width
                        strong: true
                        name: {
                            var date = new Date((dayOverlay.detail?.date || "") + "T00:00:00");
                            return isNaN(date.getTime()) ? "" : date.toLocaleDateString(Qt.locale(), "ddd d MMM");
                        }
                        value: root.usageHasTokens && !dayOverlay.detail?.missing ? root.formatTokens(dayOverlay.detail?.total || 0) + " " + root.tr("tokens") : ""
                    }

                    Repeater {
                        model: dayOverlay.detail?.groups ?? []

                        delegate: Column {
                            id: dayGroup
                            required property var modelData
                            readonly property bool named: modelData.name !== ""
                            width: dayContents.width
                            topPadding: named ? Theme.spacingXS : 0
                            spacing: 2

                            DetailLine {
                                visible: dayGroup.named
                                width: parent.width
                                strong: true
                                showSwatch: true
                                roundSwatch: true
                                swatch: dayGroup.modelData.color || "transparent"
                                name: dayGroup.modelData.name
                                value: root.formatTokens(dayGroup.modelData.tokens)
                            }

                            Repeater {
                                model: dayGroup.modelData.models

                                delegate: DetailLine {
                                    required property var modelData
                                    width: dayGroup.width
                                    indent: dayGroup.named ? Theme.spacingM : 0
                                    showSwatch: !dayGroup.named
                                    swatch: modelData.color
                                    name: modelData.name
                                    value: root.formatTokens(modelData.tokens)
                                }
                            }
                        }
                    }

                    StyledText {
                        topPadding: Theme.spacingXS
                        text: dayOverlay.detail?.missing ? root.tr("no data")
                              : dayOverlay.detail ? root.formatCount(dayOverlay.detail.requests) + " " + root.tr("requests")
                              + (dayOverlay.detail.failed > 0 ? " \u00b7 " + root.formatCount(dayOverlay.detail.failed) + " " + root.tr("failed") : "") : ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }
        }
    }
}

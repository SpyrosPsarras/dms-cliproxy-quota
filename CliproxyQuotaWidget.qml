import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "translations.js" as Tr

PluginComponent {
    id: root

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

    readonly property var visibleProviders: quota && quota.providers ? quota.providers : []

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
    readonly property real remaining: pillProvider && pillProvider.aggregate !== null ? pillProvider.aggregate : -1
    readonly property bool dataLive: quota !== null && quota.status === "ok" && quota.stale !== true
    readonly property bool anyProblem: visibleProviders.some(p => p.problem === true && !isUntracked(p.provider))
    readonly property bool drift: quota !== null && quota.drift === true

    property double nowMs: Date.now()

    readonly property var activity: pillProvider ? (pillProvider.activity || []) : []
    readonly property string todayDate: Qt.formatDate(new Date(nowMs), "yyyy-MM-dd")

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
        return Object.keys(sums).filter(m => sums[m] > 0)
            .map(m => ({ model: m, total: sums[m] }))
            .sort((a, b) => b.total - a.total);
    }

    // Generic, no model is special-cased: drop the provider prefix and date
    // stamps, words before the first number are the family, numbers the version.
    // acme-large-2-1-20250101 on provider acme becomes family Large, name Large 2.1.
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
        var family = words.join(" ");
        return { family: family, name: version === "" ? family : family + " " + version };
    }

    readonly property var familyPalette: [
        Theme.primary || "#82aaff",
        Theme.success || "#66bb6a",
        Theme.warning || "#ffca28",
        Theme.error || "#ef5350",
        Theme.tertiary || "#ab47bc",
        Theme.teal || "#26a69a"
    ]

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
            if (v)
                v.total += mt.total;
            else
                f.versions.push({ name: p.name, total: mt.total });
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

    // Survives the refresh that rebuilds the family delegates.
    property var expandedFamilies: ({})
    function toggleFamily(name) {
        var next = Object.assign({}, expandedFamilies);
        next[name] = !next[name];
        expandedFamilies = next;
    }

    readonly property var usageStats: {
        var today = { label: tr("Today"), tokens: 0, requests: 0 };
        var week = { label: tr("7 days"), tokens: 0, requests: 0 };
        for (var i = 0; i < activity.length; i++) {
            var e = activity[i];
            week.tokens += dayTokens(e);
            week.requests += e.requests;
            if (e.date === todayDate) {
                today.tokens = dayTokens(e);
                today.requests = e.requests;
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

    function focusPage(index) {
        if (visibleProviders.length === 0)
            return;
        var n = visibleProviders.length;
        var next = ((index % n) + n) % n;
        focusedProvider = visibleProviders[next].provider;
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

    function pillText() {
        if (quota === null)
            return "…";
        if (quota.status === "ok") {
            var pct = remaining < 0 ? "—" : Math.round(remaining * 100) + "%";
            return dataLive ? pct : pct + "?";
        }
        return (quota.error || root.tr("no data")) + "?";
    }

    Process {
        id: quotaProcess
        command: ["timeout", "60", "bash", root.scriptPath].concat(root.forceFetch ? ["--force"] : [])
        environment: root.scriptEnvironment
        running: false

        stdout: SplitParser {
            onRead: data => {
                var line = data.trim();
                if (line === "")
                    return;
                try {
                    root.quota = JSON.parse(line);
                    root.receivedThisRun = true;
                } catch (e) {
                }
            }
        }

        onRunningChanged: {
            if (running)
                root.receivedThisRun = false;
        }

        onExited: (exitCode, exitStatus) => {
            root.forceFetch = false;
            if (exitCode !== 0 || !root.receivedThisRun)
                root.quota = ({ status: "script-error", error: "fetch failed", stale: true, providers: [] });
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

            Canvas {
                width: root.iconSize
                height: root.iconSize
                visible: root.remaining >= 0
                anchors.verticalCenter: parent.verticalCenter
                renderStrategy: Canvas.Cooperative

                property real fraction: root.remaining
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

            DankIcon {
                name: "help"
                visible: root.remaining < 0
                size: root.iconSize
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.pillText()
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            DankIcon {
                name: "warning"
                visible: root.anyProblem
                size: root.iconSize
                color: Theme.warning
                anchors.verticalCenter: parent.verticalCenter
            }

            DankIcon {
                name: "upgrade"
                visible: root.drift
                size: root.iconSize
                color: Theme.info
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            opacity: root.dataLive ? 1 : 0.6

            Canvas {
                width: root.iconSize
                height: root.iconSize
                visible: root.remaining >= 0
                anchors.horizontalCenter: parent.horizontalCenter
                renderStrategy: Canvas.Cooperative

                property real fraction: root.remaining
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

            DankIcon {
                name: "help"
                visible: root.remaining < 0
                size: root.iconSize
                color: Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: "?"
                visible: !root.dataLive
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                color: Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }

            DankIcon {
                name: "warning"
                visible: root.anyProblem
                size: root.iconSize
                color: Theme.warning
                anchors.horizontalCenter: parent.horizontalCenter
            }

            DankIcon {
                name: "upgrade"
                visible: root.drift
                size: root.iconSize
                color: Theme.info
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

            // Everything above the scrolling area.
            readonly property real headerHeight: 40 + navTabs.height
                + (unsupportedNote.visible ? unsupportedNote.height + Theme.spacingS : 0)
                + 3 * Theme.spacingS

            // Grow with the content, from the base height up to 1.5x, then scroll.
            Binding {
                target: root
                property: "popoutHeight"
                value: Math.round(Math.min(root.basePopoutHeight * 1.5,
                                           Math.max(root.basePopoutHeight, popoutRoot.headerHeight + accountsColumn.height)))
            }
            Connections {
                target: popoutRoot.parentPopout
                function onOpened() {
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
                    height: 40

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS

                        DankIcon {
                            name: "data_usage"
                            size: 20
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: root.tr("Quota")
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS

                        StyledText {
                            text: {
                                var age = root.formatAge(root.quota ? root.quota.updatedAt : "");
                                return age === "" ? "" : root.tr("updated") + " " + age;
                            }
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
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

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.spacingS

                        Repeater {
                            model: root.visibleProviders

                            delegate: StyledRect {
                                id: providerTab
                                required property var modelData
                                required property int index
                                readonly property bool focused: index === root.focusedIndex

                                height: 36
                                width: tabContent.width + 2 * Theme.spacingM
                                radius: height / 2
                                color: focused ? Theme.withAlpha(Theme.primary, 0.16) : Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                                border.width: 1
                                border.color: focused ? Theme.withAlpha(Theme.primary, 0.45) : Theme.outlineLight

                                Behavior on width {
                                    NumberAnimation {
                                        duration: Theme.shortDuration
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                Row {
                                    id: tabContent
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS

                                    Item {
                                        width: 20
                                        height: 20
                                        anchors.verticalCenter: parent.verticalCenter
                                        opacity: providerTab.focused ? 1 : 0.55

                                        Image {
                                            anchors.fill: parent
                                            visible: root.providerIconSource(providerTab.modelData.provider) !== ""
                                            source: root.providerIconSource(providerTab.modelData.provider)
                                            sourceSize.width: 40
                                            sourceSize.height: 40
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                        }

                                        DankIcon {
                                            anchors.centerIn: parent
                                            visible: root.providerIconSource(providerTab.modelData.provider) === ""
                                            name: root.providerIcon(providerTab.modelData.provider)
                                            size: 18
                                            color: providerTab.focused ? Theme.primary : Theme.surfaceVariantText
                                        }
                                    }

                                    StyledText {
                                        visible: providerTab.focused
                                        text: providerTab.modelData.provider
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    StyledText {
                                        visible: providerTab.focused
                                        text: (providerTab.modelData.aggregate !== null ? Math.round(providerTab.modelData.aggregate * 100) + "%" : "\u2014")
                                              + (root.dataLive ? "" : "?")
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: root.dataLive && providerTab.modelData.aggregate !== null ? root.ringColor(providerTab.modelData.aggregate) : Theme.surfaceVariantText
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
                                    color: Theme.warning
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

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 2 * Theme.spacingM
                    visible: root.focusedIndex < 0
                    text: root.quota && root.quota.error ? root.quota.error : root.tr("no data")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    id: unsupportedNote
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 2 * Theme.spacingM
                    visible: root.quota && root.quota.unsupportedProviders && root.quota.unsupportedProviders.length > 0
                    text: visible ? root.tr("unsupported") + ": " + root.quota.unsupportedProviders.join(", ") : ""
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Theme.fontSizeSmall
                    font.italic: true
                    color: Theme.surfaceVariantText
                }

                DankFlickable {
                    width: parent.width
                    height: Math.max(140, root.popoutHeight - popoutRoot.headerHeight)
                    contentHeight: accountsColumn.height
                    clip: true
                    opacity: root.dataLive ? 1 : 0.6

                    Column {
                        id: accountsColumn
                        width: parent.width
                        spacing: Theme.spacingS

                        Column {
                            id: aggregateBars
                            width: accountsColumn.width - 2 * Theme.spacingM
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Theme.spacingS
                            visible: root.focusedIndex >= 0

                            Repeater {
                                model: root.pillProvider ? (root.pillProvider.aggregateGroups || []) : []

                                delegate: StyledRect {
                                    id: aggGroupCard
                                    required property var modelData
                                    required property int index
                                    readonly property bool lead: index === 0
                                    readonly property real fraction: Math.max(0, Math.min(1, modelData.remainingFraction))
                                    readonly property real paceDelta: {
                                        var ws = modelData.windowSeconds;
                                        var rt = modelData.resetTime;
                                        if (!ws || !rt)
                                            return NaN;
                                        var remainMs = new Date(rt).getTime() - root.nowMs;
                                        if (isNaN(remainMs) || remainMs < 0)
                                            return NaN;
                                        var elapsed = 1 - remainMs / (ws * 1000);
                                        elapsed = Math.max(0, Math.min(1, elapsed));
                                        return (1 - fraction) - elapsed;
                                    }

                                    width: aggregateBars.width
                                    height: lead ? 124 : 88
                                    radius: Theme.cornerRadius
                                    color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: Theme.spacingM
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.spacingL

                                        Item {
                                            width: aggGroupCard.lead ? 96 : 64
                                            height: width
                                            anchors.verticalCenter: parent.verticalCenter

                                            Canvas {
                                                anchors.fill: parent
                                                renderStrategy: Canvas.Cooperative

                                                property real fraction: aggGroupCard.fraction
                                                onFractionChanged: requestPaint()
                                                onWidthChanged: requestPaint()

                                                onPaint: {
                                                    var ctx = getContext("2d");
                                                    ctx.reset();
                                                    var cx = width / 2, cy = height / 2, r = width * 0.42, lw = width * 0.09;

                                                    ctx.beginPath();
                                                    ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                                                    ctx.lineWidth = lw;
                                                    ctx.strokeStyle = Theme.surfaceVariant;
                                                    ctx.stroke();

                                                    if (fraction > 0) {
                                                        ctx.beginPath();
                                                        ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * fraction);
                                                        ctx.lineWidth = lw;
                                                        ctx.strokeStyle = root.ringColor(fraction);
                                                        ctx.lineCap = "round";
                                                        ctx.stroke();
                                                    }
                                                }
                                            }

                                            StyledText {
                                                anchors.centerIn: parent
                                                text: Math.round(aggGroupCard.fraction * 100) + "%"
                                                font.pixelSize: aggGroupCard.lead ? Theme.fontSizeXLarge : Theme.fontSizeMedium
                                                font.weight: Font.DemiBold
                                                color: Theme.surfaceText
                                            }
                                        }

                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: aggGroupCard.lead ? 4 : 2

                                            StyledText {
                                                text: aggGroupCard.modelData.label || aggGroupCard.modelData.id
                                                font.pixelSize: aggGroupCard.lead ? Theme.fontSizeLarge : Theme.fontSizeMedium
                                                font.weight: Font.Medium
                                                color: Theme.surfaceText
                                            }

                                            StyledText {
                                                text: Math.round(aggGroupCard.fraction * 100) + "% " + root.tr("remaining")
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: root.ringColor(aggGroupCard.fraction)
                                            }

                                            StyledText {
                                                visible: text !== ""
                                                text: root.formatCountdown(aggGroupCard.modelData.resetTime)
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceVariantText
                                            }

                                            StyledText {
                                                visible: !isNaN(aggGroupCard.paceDelta)
                                                text: {
                                                    var pct = Math.round(Math.abs(aggGroupCard.paceDelta) * 100);
                                                    if (pct < 1)
                                                        return root.tr("on pace");
                                                    return pct + "% " + (aggGroupCard.paceDelta > 0 ? root.tr("over pace") : root.tr("under pace"));
                                                }
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: isNaN(aggGroupCard.paceDelta) || Math.round(Math.abs(aggGroupCard.paceDelta) * 100) < 1
                                                       ? Theme.surfaceVariantText
                                                       : aggGroupCard.paceDelta > 0 ? Theme.warning : Theme.success
                                            }
                                        }
                                    }
                                }
                            }

                        }

                        StyledRect {
                            id: tokensCard
                            visible: root.modelTotals.length > 0
                            width: accountsColumn.width - 2 * Theme.spacingM
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: tokensContent.height + 2 * Theme.spacingM
                            radius: Theme.cornerRadius
                            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

                            Column {
                                id: tokensContent
                                anchors.centerIn: parent
                                width: parent.width - 2 * Theme.spacingM
                                spacing: Theme.spacingS

                                StyledText {
                                    text: root.tr("Token Consumption")
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                }

                                Row {
                                    width: parent.width

                                    Repeater {
                                        model: root.usageStats

                                        delegate: Column {
                                            id: statColumn
                                            required property var modelData
                                            width: tokensContent.width / root.usageStats.length
                                            spacing: 2

                                            StyledText {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: statColumn.modelData.label
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceVariantText
                                            }

                                            StyledText {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: root.formatTokens(statColumn.modelData.tokens)
                                                font.pixelSize: Theme.fontSizeXLarge
                                                color: Theme.primary
                                            }

                                            StyledText {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: statColumn.modelData.requests + " " + root.tr("requests")
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceVariantText
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        StyledRect {
                            id: activityCard
                            readonly property bool hasTokens: root.modelTotals.length > 0
                            readonly property real maxValue: {
                                var m = 0;
                                for (var i = 0; i < root.activity.length; i++)
                                    m = Math.max(m, value(root.activity[i]));
                                return m;
                            }

                            visible: root.activity.length > 0
                            width: accountsColumn.width - 2 * Theme.spacingM
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: activityContent.height + 2 * Theme.spacingM
                            radius: Theme.cornerRadius
                            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

                            function value(entry) {
                                return hasTokens ? root.dayTokens(entry) : entry.requests;
                            }

                            function dayTooltip(entry) {
                                var byName = {};
                                var names = [];
                                var t = entry.tokens || {};
                                for (var i = 0; i < root.modelTotals.length; i++) {
                                    var v = t[root.modelTotals[i].model] || 0;
                                    if (v <= 0) continue;
                                    var n = root.parseModel(root.modelTotals[i].model).name;
                                    if (!(n in byName)) { byName[n] = 0; names.push(n); }
                                    byName[n] += v;
                                }
                                var lines = names.map(n => n + "  " + root.formatTokens(byName[n]));
                                var req = entry.requests + " " + root.tr("requests");
                                if (entry.failed > 0) req += " \u00b7 " + entry.failed + " " + root.tr("failed");
                                lines.push(req);
                                return lines.join("\n");
                            }

                            Column {
                                id: activityContent
                                anchors.centerIn: parent
                                width: parent.width - 2 * Theme.spacingM
                                spacing: Theme.spacingS

                                StyledText {
                                    text: root.tr("Daily Activity")
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                }

                                Row {
                                    id: barsRow
                                    width: parent.width

                                    Repeater {
                                        model: root.activity

                                        delegate: Column {
                                            id: dayColumn
                                            required property var modelData
                                            readonly property real value: activityCard.value(modelData)
                                            readonly property bool isToday: modelData.date === root.todayDate
                                            width: barsRow.width / root.activity.length
                                            spacing: 4

                                            StyledText {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: activityCard.hasTokens ? root.formatTokens(dayColumn.value) : dayColumn.value
                                                font.pixelSize: Theme.fontSizeSmall - 2
                                                color: Theme.surfaceVariantText
                                            }

                                            Item {
                                                width: parent.width
                                                height: 64

                                                Column {
                                                    visible: activityCard.hasTokens
                                                    anchors.bottom: parent.bottom
                                                    anchors.horizontalCenter: parent.horizontalCenter

                                                    Repeater {
                                                        model: activityCard.hasTokens ? root.modelFamilies.slice().reverse() : []

                                                        delegate: Rectangle {
                                                            required property var modelData
                                                            readonly property real value: root.familyTokens(dayColumn.modelData, modelData)
                                                            width: Math.min(36, dayColumn.width - Theme.spacingS)
                                                            height: value > 0 && activityCard.maxValue > 0 ? Math.max(1, 64 * value / activityCard.maxValue) : 0
                                                            color: modelData.color
                                                        }
                                                    }
                                                }

                                                Rectangle {
                                                    visible: !activityCard.hasTokens || dayColumn.value <= 0
                                                    anchors.bottom: parent.bottom
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    width: Math.min(36, parent.width - Theme.spacingS)
                                                    radius: 4
                                                    height: activityCard.maxValue > 0 ? Math.max(3, 64 * dayColumn.value / activityCard.maxValue) : 3
                                                    color: dayColumn.value <= 0 ? Theme.surfaceVariant
                                                         : dayColumn.isToday ? Theme.primary
                                                         : Theme.withAlpha(Theme.primary, 0.35)
                                                }

                                                MouseArea {
                                                    id: dayHover
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    acceptedButtons: Qt.NoButton
                                                }

                                                ToolTip.visible: dayHover.containsMouse
                                                ToolTip.delay: 250
                                                ToolTip.text: activityCard.dayTooltip(dayColumn.modelData)
                                            }

                                            StyledText {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: {
                                                    var d = new Date(dayColumn.modelData.date + "T00:00:00");
                                                    return isNaN(d.getTime()) ? "" : d.toLocaleDateString(Qt.locale(), "ddd");
                                                }
                                                font.pixelSize: Theme.fontSizeSmall - 2
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
                            visible: root.modelTotals.length > 0
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
                                    model: root.modelFamilies

                                    delegate: Column {
                                        id: familyRow
                                        required property var modelData
                                        readonly property bool multi: modelData.versions.length > 1
                                        readonly property bool expanded: multi && root.expandedFamilies[modelData.family] === true
                                        width: modelsContent.width
                                        spacing: 4

                                        Item {
                                            width: parent.width
                                            height: familyLabel.height

                                            StyledText {
                                                id: familyLabel
                                                anchors.left: parent.left
                                                anchors.right: familyRow.multi ? familyChevron.left : parent.right
                                                elide: Text.ElideRight
                                                text: (familyRow.multi ? familyRow.modelData.family : familyRow.modelData.versions[0].name)
                                                      + "  " + root.formatTokens(familyRow.modelData.total)
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceText
                                            }

                                            DankIcon {
                                                id: familyChevron
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: familyRow.multi
                                                name: familyRow.expanded ? "expand_less" : "expand_more"
                                                size: 16
                                                color: Theme.surfaceVariantText
                                            }

                                            MouseArea {
                                                anchors.fill: parent
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
                                                width: parent.width * familyRow.modelData.total / root.modelFamilies[0].total
                                                height: parent.height
                                                radius: parent.radius
                                                color: familyRow.modelData.color
                                            }
                                        }

                                        Column {
                                            id: versionList
                                            visible: familyRow.expanded
                                            width: parent.width
                                            leftPadding: Theme.spacingM
                                            topPadding: 2
                                            spacing: 4

                                            Repeater {
                                                model: familyRow.expanded ? familyRow.modelData.versions : []

                                                delegate: Column {
                                                    id: versionRow
                                                    required property var modelData
                                                    width: versionList.width - Theme.spacingM
                                                    spacing: 2

                                                    StyledText {
                                                        width: parent.width
                                                        elide: Text.ElideRight
                                                        text: versionRow.modelData.name + "  " + root.formatTokens(versionRow.modelData.total)
                                                        font.pixelSize: Theme.fontSizeSmall - 1
                                                        color: Theme.surfaceVariantText
                                                    }

                                                    Rectangle {
                                                        width: parent.width
                                                        height: 4
                                                        radius: 2
                                                        color: Theme.surfaceVariant

                                                        Rectangle {
                                                            width: parent.width * versionRow.modelData.total / familyRow.modelData.total
                                                            height: parent.height
                                                            radius: parent.radius
                                                            color: Theme.withAlpha(familyRow.modelData.color, 0.6)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            width: accountsColumn.width - 2 * Theme.spacingM
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: 32
                            visible: root.focusedIndex >= 0

                            StyledText {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.tr("Accounts")
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: Theme.surfaceVariantText
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingXS

                                DankActionButton {
                                    buttonSize: 26
                                    iconName: root.pillProvider && root.isUntracked(root.pillProvider.provider) ? "notifications_off" : "notifications"
                                    iconColor: root.pillProvider && root.isUntracked(root.pillProvider.provider) ? Theme.surfaceVariantText : Theme.surfaceText
                                    tooltipText: root.tr("Warnings on the taskbar")
                                    onClicked: if (root.pillProvider) root.toggleTracking(root.pillProvider.provider)
                                }

                            }
                        }

                        Repeater {
                            model: root.pillProvider ? root.pillProvider.accounts : []

                            delegate: StyledRect {
                                id: accountCard
                                required property var modelData

                                readonly property bool healthy: !modelData.disabled && !modelData.unavailable
                                                                && (modelData.status === "active" || modelData.supported === false)
                                property bool expanded: healthy && !modelData.noQuota

                                width: accountsColumn.width - 2 * Theme.spacingM
                                anchors.horizontalCenter: parent.horizontalCenter
                                height: accountHeader.height + (expanded ? accountBody.height + Theme.spacingS : 0)
                                radius: Theme.cornerRadius
                                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                                border.width: 1
                                border.color: accountCard.healthy ? Theme.outlineLight : Theme.withAlpha(Theme.error, 0.5)
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

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: accountCard.expanded = !accountCard.expanded
                                    }

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: Theme.spacingM
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.spacingS

                                        Rectangle {
                                            width: 8
                                            height: 8
                                            radius: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: accountCard.modelData.disabled || accountCard.modelData.unavailable
                                                   || accountCard.modelData.supported === false
                                                   ? Theme.surfaceVariantText
                                                   : accountCard.modelData.status !== "active" ? Theme.error : Theme.success
                                        }

                                        StyledText {
                                            text: accountCard.modelData.label || accountCard.modelData.account
                                            font.pixelSize: Theme.fontSizeMedium
                                            color: Theme.surfaceText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            visible: accountCard.modelData.disabled
                                            text: root.tr("disabled")
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.error
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            visible: accountCard.modelData.unavailable
                                            text: root.tr("unavailable")
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.warning
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            visible: accountCard.modelData.supported === false
                                            text: root.tr("unsupported")
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    DankIcon {
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

                                    Row {
                                        spacing: Theme.spacingM

                                        StyledText {
                                            text: accountCard.modelData.status
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                        }

                                        StyledText {
                                            visible: !!accountCard.modelData.lastRequestAt
                                            text: root.tr("last request") + " " + root.formatAge(accountCard.modelData.lastRequestAt)
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                        }

                                        Row {
                                            spacing: 2
                                            DankIcon {
                                                name: "check"
                                                size: 13
                                                color: Theme.success
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            StyledText {
                                                text: String(accountCard.modelData.success)
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceVariantText
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        Row {
                                            spacing: 2
                                            DankIcon {
                                                name: "close"
                                                size: 13
                                                color: accountCard.modelData.failed > 0 ? Theme.error : Theme.surfaceVariantText
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            StyledText {
                                                text: String(accountCard.modelData.failed)
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceVariantText
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }

                                    StyledText {
                                        visible: accountCard.modelData.error !== ""
                                        width: parent.width
                                        text: accountCard.modelData.error
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.italic: accountCard.healthy
                                        color: accountCard.healthy ? Theme.surfaceVariantText : Theme.error
                                        wrapMode: Text.WordWrap
                                    }

                                    StyledText {
                                        visible: accountCard.modelData.noQuota
                                        text: root.tr("no quota reported")
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.italic: true
                                        color: Theme.surfaceVariantText
                                    }

                                    Repeater {
                                        model: accountCard.modelData.groups

                                        delegate: Column {
                                            id: groupRow
                                            required property var modelData
                                            width: accountBody.width
                                            spacing: 2

                                            Item {
                                                width: parent.width
                                                height: groupLabel.height

                                                StyledText {
                                                    id: groupLabel
                                                    anchors.left: parent.left
                                                    text: groupRow.modelData.label || groupRow.modelData.id
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    color: Theme.surfaceText
                                                }

                                                StyledText {
                                                    anchors.right: remainingPct.left
                                                    anchors.rightMargin: Theme.spacingS
                                                    text: root.formatCountdown(groupRow.modelData.resetTime)
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    color: Theme.surfaceVariantText
                                                }

                                                StyledText {
                                                    id: remainingPct
                                                    anchors.right: parent.right
                                                    text: Math.round(groupRow.modelData.remainingFraction * 100) + "%"
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    color: root.ringColor(groupRow.modelData.remainingFraction)
                                                }
                                            }

                                            Rectangle {
                                                width: parent.width
                                                height: 6
                                                radius: 3
                                                color: Theme.surfaceVariant

                                                Rectangle {
                                                    width: parent.width * Math.max(0, Math.min(1, groupRow.modelData.remainingFraction))
                                                    height: parent.height
                                                    radius: parent.radius
                                                    color: root.ringColor(groupRow.modelData.remainingFraction)
                                                }
                                            }
                                        }
                                    }

                                    Item {
                                        width: 1
                                        height: Theme.spacingXS
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

import QtQuick
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

    // Settings reach get-quota as environment variables. A key the user never
    // touched stays out of the map, so the script's own defaults apply; a
    // cleared vault command is passed as "" and disables that source.
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

    // The whole flat document get-quota prints. null until the first run lands.
    property var quota: null

    // Per-provider opt-out, persisted as a comma-separated list in the plugin
    // settings. An untracked provider's problems stay off the taskbar triangle
    // and tab dot; its page always stays in the carousel — the widget never
    // hides data, it only silences alarms.
    function parseList(raw) {
        // Deduplicated: a hand-edited "acme, acme" must not need two bell
        // clicks to re-enable tracking.
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

    // Every provider the server reports, always.
    readonly property var visibleProviders: quota && quota.providers ? quota.providers : []

    // The carousel page currently selected. It alone drives the pill's ring,
    // and it survives restarts through the plugin settings.
    property string focusedProvider: pluginData.focusedProvider || ""
    // Index of the focused provider, falling back to the first page when the
    // persisted provider is absent from the payload.
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
    // Remaining fraction, or -1 when there is nothing trustworthy to show.
    readonly property real remaining: pillProvider && pillProvider.aggregate !== null ? pillProvider.aggregate : -1
    readonly property bool dataLive: quota !== null && quota.status === "ok" && quota.stale !== true
    // A problem on any provider the user still tracks reaches the taskbar,
    // focused page or not. Untracked providers stay silent.
    readonly property bool anyProblem: visibleProviders.some(p => p.problem === true && !isUntracked(p.provider))
    // The server offers a newer contract, or sent a payload schema this widget
    // was not written against.
    readonly property bool drift: quota !== null && quota.drift === true

    // Ticks while the popout is open so countdowns and ages stay current.
    property double nowMs: Date.now()

    function focusPage(index) {
        if (visibleProviders.length === 0)
            return;
        var n = visibleProviders.length;
        var next = ((index % n) + n) % n;
        focusedProvider = visibleProviders[next].provider;
        pluginService?.savePluginData("cliproxyQuota", "focusedProvider", focusedProvider);
    }

    // Icon lookup is the one place a provider name may appear in this source
    // (see tests/test-qml-syntax.sh); every other line treats providers as data.
    // An unknown provider gets the generic icon, never dropped.
    // Brand logo asset for a provider's icon, or "" for the DankIcon fallback.
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

    // "2m" / "3h" / "5d" since an ISO timestamp, or "" when unusable.
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

    // Countdown to an ISO reset timestamp: "resets in 2h 15m".
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

    // True once the run currently executing has produced a parseable document.
    // A run that exits without one (timeout, killed !command, launch failure)
    // must not leave the previous numbers on display as if they were live.
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
            // Stale numbers stay visible but never pose as live: dimmed, "?".
            return dataLive ? pct : pct + "?";
        }
        // No payload behind this state: state the reason, never a number.
        // Carries e.g. "server has no quota plugin (pi-bridge)" verbatim.
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

    // The pill mirrors the carousel's focused page.
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            // Dimmed while the numbers are not live: never state a percentage
            // the data cannot back up.
            opacity: root.dataLive ? 1 : 0.6

            Canvas {
                width: root.iconSize
                height: root.iconSize
                // A provider with no quota to draw gets a glyph, never an
                // empty ring pretending to be 0%.
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

                    // The ring fills with what REMAINS: full ring = full quota.
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

            // The vertical bar has no room for prose, but it must still say
            // "these numbers are not live": a "?" appears whenever dimmed.
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
    popoutHeight: 620

    popoutContent: Component {
        FocusScope {
            id: popoutRoot
            implicitWidth: root.popoutWidth
            implicitHeight: root.popoutHeight
            focus: true

            property var parentPopout: null
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

            // Countdowns and ages tick only while the popout is visible.
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

                // --- Header: title, server cache age, refresh ---
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

                // --- Provider tabs: one per provider in server order. The
                // focused tab expands with the provider's name and aggregate;
                // ←/→ still page, clicking a tab jumps. Replaces the arrows —
                // every provider is visible at a glance, like its peers do it.
                Item {
                    id: navTabs
                    width: parent.width
                    height: 44
                    visible: root.focusedIndex >= 0
                    // The headline is a number too: dim it with the rest the
                    // moment the data stops being live.
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

                                // The taskbar glyph says "something is wrong
                                // somewhere"; this dot says where — straight on
                                // the offending provider's tab.
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

                // A terminal state names itself: "server has no quota plugin
                // (pi-bridge)", "key unavailable", "proxy unreachable" — the
                // script's words, not a generic shrug.
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

                // Providers the bridge cannot report on — informational, never
                // a failure, never part of anyProblem.
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

                // --- Focused provider page: aggregate group cards, then the
                // expandable account cards, in ONE scroll area — the server may
                // report any number of groups, and every account must remain
                // reachable below them.
                DankFlickable {
                    width: parent.width
                    height: Math.max(140, root.popoutHeight - 40 - navTabs.height
                            - (unsupportedNote.visible ? unsupportedNote.height + Theme.spacingS : 0)
                            - 3 * Theme.spacingS)
                    contentHeight: accountsColumn.height
                    clip: true
                    // Everything below reflects the fetched document; dim it the
                    // moment the numbers stop being live.
                    opacity: root.dataLive ? 1 : 0.6

                    Column {
                        id: accountsColumn
                        width: parent.width
                        spacing: Theme.spacingS

                        // Aggregate view: the winning account's groups, one card
                        // each with a large remaining-ring.
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
                                    readonly property real fraction: Math.max(0, Math.min(1, modelData.remainingFraction))
                                    // Used fraction versus elapsed fraction of the
                                    // window. NaN (no duration, no reset time, or a
                                    // window that has not started) keeps pace silent.
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
                                    height: 88
                                    radius: Theme.cornerRadius
                                    color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: Theme.spacingM
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.spacingL

                                        Item {
                                            width: 64
                                            height: 64
                                            anchors.verticalCenter: parent.verticalCenter

                                            Canvas {
                                                anchors.fill: parent
                                                renderStrategy: Canvas.Cooperative

                                                property real fraction: aggGroupCard.fraction
                                                onFractionChanged: requestPaint()

                                                onPaint: {
                                                    var ctx = getContext("2d");
                                                    ctx.reset();
                                                    var cx = width / 2, cy = height / 2, r = width * 0.42, lw = width * 0.09;

                                                    ctx.beginPath();
                                                    ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                                                    ctx.lineWidth = lw;
                                                    ctx.strokeStyle = Theme.surfaceVariant;
                                                    ctx.stroke();

                                                    // The ring fills with what REMAINS.
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
                                                font.pixelSize: Theme.fontSizeMedium
                                                font.weight: Font.DemiBold
                                                color: Theme.surfaceText
                                            }
                                        }

                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 2

                                            StyledText {
                                                text: aggGroupCard.modelData.label || aggGroupCard.modelData.id
                                                font.pixelSize: Theme.fontSizeMedium
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

                        // Accounts header with the focused provider's opt-out:
                        // the bell keeps or removes it from the taskbar triangle.
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

                                // Healthy = serving. An error string on a serving
                                // account (unreadable quota meter upstream) is
                                // degraded telemetry, not ill health; so is
                                // supported:false, a capability statement.
                                readonly property bool healthy: !modelData.disabled && !modelData.unavailable
                                                                && (modelData.status === "active" || modelData.supported === false)
                                // Live accounts open with their bars showing; a
                                // disabled or empty account starts folded.
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

                                    // Health line: status, last request, counters.
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
                                        // The text explains; it alarms only when the
                                        // account is actually not serving.
                                        font.italic: accountCard.healthy
                                        color: accountCard.healthy ? Theme.surfaceVariantText : Theme.error
                                        wrapMode: Text.WordWrap
                                    }

                                    // groups: [] means the provider reported no
                                    // quota — said in words, never shown as 0%.
                                    StyledText {
                                        visible: accountCard.modelData.noQuota
                                        text: root.tr("no quota reported")
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.italic: true
                                        color: Theme.surfaceVariantText
                                    }

                                    // One bar per group, filled with what REMAINS.
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

                        // --- Daily activity: requests per day, deltas of the
                        // proxy's counters accumulated locally. Appears once a
                        // second day of history exists.
                        StyledText {
                            visible: activityCard.visible
                            text: root.tr("Daily Activity")
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: Theme.surfaceVariantText
                            leftPadding: Theme.spacingM
                        }

                        StyledRect {
                            id: activityCard
                            readonly property var activity: root.pillProvider ? (root.pillProvider.activity || []) : []
                            readonly property real maxRequests: {
                                var m = 0;
                                for (var i = 0; i < activity.length; i++)
                                    m = Math.max(m, activity[i].requests);
                                return m;
                            }

                            visible: activity.length > 0
                            width: accountsColumn.width - 2 * Theme.spacingM
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: 96
                            radius: Theme.cornerRadius
                            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

                            Row {
                                anchors.centerIn: parent
                                spacing: Theme.spacingM

                                Repeater {
                                    model: activityCard.activity

                                    delegate: Column {
                                        id: dayColumn
                                        required property var modelData
                                        spacing: 2

                                        StyledText {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: dayColumn.modelData.requests
                                            font.pixelSize: Theme.fontSizeSmall - 2
                                            color: Theme.surfaceVariantText
                                        }

                                        Item {
                                            width: 26
                                            height: 40
                                            anchors.horizontalCenter: parent.horizontalCenter

                                            Rectangle {
                                                anchors.bottom: parent.bottom
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: 18
                                                radius: 3
                                                height: activityCard.maxRequests > 0
                                                        ? Math.max(3, 40 * dayColumn.modelData.requests / activityCard.maxRequests)
                                                        : 3
                                                color: dayColumn.modelData.requests > 0 ? Theme.primary : Theme.surfaceVariant
                                            }
                                        }

                                        StyledText {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: {
                                                var d = new Date(dayColumn.modelData.date + "T00:00:00");
                                                return isNaN(d.getTime()) ? "" : d.toLocaleDateString(Qt.locale(), "ddd");
                                            }
                                            font.pixelSize: Theme.fontSizeSmall - 2
                                            color: Theme.surfaceVariantText
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
}

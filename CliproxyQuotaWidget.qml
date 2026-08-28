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

    // The carousel page currently selected. It alone drives the pill's ring,
    // and it survives restarts through the plugin settings.
    property string focusedProvider: pluginData.focusedProvider || ""
    // Index of the focused provider, falling back to the first page when the
    // persisted provider is absent from the payload.
    readonly property int focusedIndex: {
        if (!quota || !quota.providers || quota.providers.length === 0)
            return -1;
        for (var i = 0; i < quota.providers.length; i++) {
            if (quota.providers[i].provider === focusedProvider)
                return i;
        }
        return 0;
    }
    readonly property var pillProvider: focusedIndex >= 0 ? quota.providers[focusedIndex] : null
    // Remaining fraction, or -1 when there is nothing trustworthy to show.
    readonly property real remaining: pillProvider && pillProvider.aggregate !== null ? pillProvider.aggregate : -1
    readonly property bool dataLive: quota !== null && quota.status === "ok" && quota.stale !== true
    // A problem on ANY provider reaches the taskbar, focused page or not.
    readonly property bool anyProblem: quota !== null && quota.anyProblem === true
    // The server offers a newer contract, or sent a payload schema this widget
    // was not written against.
    readonly property bool drift: quota !== null && quota.drift === true

    // Ticks while the popout is open so countdowns and ages stay current.
    property double nowMs: Date.now()

    function focusPage(index) {
        if (!quota || !quota.providers || quota.providers.length === 0)
            return;
        var n = quota.providers.length;
        var next = ((index % n) + n) % n;
        focusedProvider = quota.providers[next].provider;
        pluginService?.savePluginData("cliproxyQuota", "focusedProvider", focusedProvider);
    }

    // Icon lookup is the one place a provider name may appear in this source
    // (see tests/test-qml-syntax.sh); every other line treats providers as data.
    // An unknown provider gets the generic icon, never dropped.
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
    popoutHeight: 540

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

                // --- Carousel navigation: ‹ provider headline › ---
                Item {
                    width: parent.width
                    height: 48
                    visible: root.focusedIndex >= 0
                    // The headline is a number too: dim it with the rest the
                    // moment the data stops being live.
                    opacity: root.dataLive ? 1 : 0.6

                    DankActionButton {
                        id: leftArrow
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "chevron_left"
                        buttonSize: 36
                        onClicked: root.focusPage(root.focusedIndex - 1)
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.spacingS

                        DankIcon {
                            name: root.providerIcon(root.pillProvider ? root.pillProvider.provider : "")
                            size: 22
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: root.pillProvider ? root.pillProvider.provider : ""
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: (root.remaining >= 0 ? Math.round(root.remaining * 100) + "%" : "\u2014")
                                  + (root.dataLive ? "" : "?")
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Medium
                            color: root.dataLive && root.remaining >= 0 ? root.ringColor(root.remaining) : Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    DankActionButton {
                        id: rightArrow
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "chevron_right"
                        buttonSize: 36
                        onClicked: root.focusPage(root.focusedIndex + 1)
                    }

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        text: root.quota && root.quota.providers ? (root.focusedIndex + 1) + "/" + root.quota.providers.length : ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }

                // --- Aggregate view: the winning account's groups, one bar
                // each with its reset countdown — the page's headline detail.
                Column {
                    id: aggregateBars
                    width: parent.width - 2 * Theme.spacingM
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.spacingXS
                    visible: root.focusedIndex >= 0
                    opacity: root.dataLive ? 1 : 0.6

                    Repeater {
                        model: root.pillProvider ? (root.pillProvider.aggregateGroups || []) : []

                        delegate: Column {
                            id: aggGroupRow
                            required property var modelData
                            width: aggregateBars.width
                            spacing: 2

                            Item {
                                width: parent.width
                                height: aggGroupLabel.height

                                StyledText {
                                    id: aggGroupLabel
                                    anchors.left: parent.left
                                    text: aggGroupRow.modelData.label || aggGroupRow.modelData.id
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceText
                                }

                                StyledText {
                                    anchors.right: aggGroupPct.left
                                    anchors.rightMargin: Theme.spacingS
                                    text: root.formatCountdown(aggGroupRow.modelData.resetTime)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }

                                StyledText {
                                    id: aggGroupPct
                                    anchors.right: parent.right
                                    text: Math.round(aggGroupRow.modelData.remainingFraction * 100) + "%"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: root.ringColor(aggGroupRow.modelData.remainingFraction)
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: 6
                                radius: 3
                                color: Theme.surfaceVariant

                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, aggGroupRow.modelData.remainingFraction))
                                    height: parent.height
                                    radius: parent.radius
                                    color: root.ringColor(aggGroupRow.modelData.remainingFraction)
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

                // --- Focused provider page: expandable account cards ---
                DankFlickable {
                    width: parent.width
                    height: root.popoutHeight - 40 - 48 - aggregateBars.height
                            - (unsupportedNote.visible ? unsupportedNote.height + Theme.spacingS : 0)
                            - 4 * Theme.spacingS
                    contentHeight: accountsColumn.height
                    clip: true
                    // Everything below reflects the fetched document; dim it the
                    // moment the numbers stop being live.
                    opacity: root.dataLive ? 1 : 0.6

                    Column {
                        id: accountsColumn
                        width: parent.width
                        spacing: Theme.spacingS

                        Repeater {
                            model: root.pillProvider ? root.pillProvider.accounts : []

                            delegate: StyledRect {
                                id: accountCard
                                required property var modelData

                                // supported:false is information, not ill health:
                                // its error explains why the bridge cannot serve it.
                                readonly property bool healthy: !modelData.disabled && !modelData.unavailable
                                                                && (modelData.error === "" || modelData.supported === false)
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
                                                   : accountCard.modelData.error !== "" ? Theme.error : Theme.success
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
                                        // Neutral when the account is unsupported: the
                                        // text explains, it does not alarm.
                                        font.italic: accountCard.modelData.supported === false
                                        color: accountCard.modelData.supported === false ? Theme.surfaceVariantText : Theme.error
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
                    }
                }
            }
        }
    }
}

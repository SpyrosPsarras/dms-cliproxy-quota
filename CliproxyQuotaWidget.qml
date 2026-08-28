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

    // The whole flat document get-quota prints. null until the first run lands.
    property var quota: null

    // T1: the pill renders the first provider. The carousel (T3) replaces this
    // with the focused provider.
    readonly property var pillProvider: quota && quota.providers && quota.providers.length > 0 ? quota.providers[0] : null
    // Remaining fraction, or -1 when there is nothing trustworthy to show.
    readonly property real remaining: pillProvider && pillProvider.aggregate !== null ? pillProvider.aggregate : -1
    readonly property bool dataLive: quota !== null && quota.status === "ok" && quota.stale !== true

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
        if (!dataLive)
            return root.tr("no data") + "?";
        if (remaining < 0)
            return "—";
        return Math.round(remaining * 100) + "%";
    }

    Process {
        id: quotaProcess
        command: ["timeout", "60", "bash", root.scriptPath].concat(root.forceFetch ? ["--force"] : [])
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
            // Dimmed while the numbers are not live: never state a percentage
            // the data cannot back up.
            opacity: root.dataLive ? 1 : 0.6

            Canvas {
                width: root.iconSize
                height: root.iconSize
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

            StyledText {
                text: root.pillText()
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                color: Theme.surfaceText
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
        }
    }
}

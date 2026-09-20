import QtQuick
import qs.Config as Config
import qs.Services as Services

// The scannable Wi-Fi network list, currently used by
// Settings/sections/Connectivity.qml's Wi-Fi group — one implementation
// so the list/connect logic exists in one place, shareable with any future
// caller that needs the same UI.
// `active` controls when a scan is triggered: Settings' Connectivity
// section only exists while it's the loaded section (Settings/Settings.qml's
// Loader), so the default `true` fires a scan exactly once per visit
// there. A caller that stays permanently instantiated behind a `visible:`
// binding instead should pass `active` explicitly, tied to its own
// visibility — otherwise `Component.onCompleted` fires once at shell
// startup regardless of whether that surface is ever opened.
// Services/WifiBridge.qml owns the scan/connect state and every nmcli call
// (the fenced service-surface rule, phi-shell/CLAUDE.md). Tapping a row
// that is already connected does nothing. Tapping an open or already-
// known network connects with no password needed. A secured network this
// device has never joined before is NOT tappable here — see Services/
// WifiBridge.qml's own header for why (a password field here would put
// the secret on the process command line, world-readable via
// /proc/<pid>/cmdline) — it shows a plain "Secured" status and directs to
// the existing "Manage networks…" (nmtui) button, which already has a
// real password prompt.
Item {
    id: root

    property bool active: true
    width: parent ? parent.width : 0
    implicitHeight: col.implicitHeight

    onActiveChanged: if (root.active) Services.WifiBridge.rescan()
    Component.onCompleted: if (root.active) Services.WifiBridge.rescan()

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real gap: root.chWidth * Config.Appearance.space1

    Column {
        id: col
        width: parent.width
        spacing: root.gap

        // An `Item` with the status text/indicator anchored left and the
        // button anchored right, rather than a plain `Row` — a `Row` packs
        // every child snug against the previous one from the left edge
        // instead of pushing the last one to the far side.
        Item {
            width: parent.width
            implicitHeight: Math.max(scanStatusRow.implicitHeight, refreshBtn.height)

            Row {
                id: scanStatusRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "label"
                    visible: !Services.WifiBridge.scanning
                    text: Services.WifiBridge.scannedNetworks.length + (Services.WifiBridge.scannedNetworks.length === 1 ? " network found" : " networks found")
                }
                // A real animated "still working" cue (Widgets/Dots)
                // rather than a static "Scanning…" that never visibly
                // changes.
                Row {
                    visible: Services.WifiBridge.scanning
                    anchors.verticalCenter: parent.verticalCenter
                    StyledText { kind: "label"; text: "Scanning" }
                    Dots {}
                }
            }
            SmallButton {
                id: refreshBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: "Refresh"
                loading: Services.WifiBridge.scanning
                onClicked: Services.WifiBridge.rescan()
            }
        }

        StyledText {
            width: parent.width
            visible: Services.WifiBridge.scanError.length > 0
            tone: "error"
            wrapMode: Text.WordWrap
            text: Services.WifiBridge.scanError
        }
        StyledText {
            width: parent.width
            visible: Services.WifiBridge.connectError.length > 0
            tone: "error"
            wrapMode: Text.WordWrap
            text: Services.WifiBridge.connectError
        }

        // Only for the FIRST scan (nothing to show yet) — a rescan that
        // already has a result list keeps showing it while it refreshes
        // (the Refresh button's own `loading` already covers that case);
        // replacing a real, useful list with a skeleton on every rescan
        // would be a regression, not an improvement.
        Skeleton {
            width: parent.width
            visible: Services.WifiBridge.scanning && Services.WifiBridge.scannedNetworks.length === 0
            count: 3
        }

        Repeater {
            model: Services.WifiBridge.scannedNetworks

            delegate: ListRow {
                // `thin` is opt-in — see Widgets/ListRow.qml's own header
                // for why the compact look isn't ListRow's default.
                thin: true
                width: col.width
                label: modelData.ssid
                value: modelData.connected
                    ? ("Connected · " + modelData.signal + "%")
                    : (modelData.known
                        ? ("Saved · " + modelData.signal + "%")
                        : (modelData.secured
                            ? ("Secured · " + modelData.signal + "%")
                            : ("Open · " + modelData.signal + "%")))
                // `enabled` reflects whether a tap actually does anything
                // ListRow's own disabled dimming and hover/cursor handlers
                // key off `enabled`, so a secured-never-joined or
                // already-connected row reads as inert instead of looking
                // clickable while silently doing nothing.
                readonly property bool _actionable: !modelData.connected
                    && !(modelData.secured && !modelData.known)
                enabled: _actionable
                onActivated: {
                    if (!_actionable) return
                    Services.WifiBridge.connectToKnownNetwork(modelData.ssid)
                }
            }
        }

        StyledText {
            width: parent.width
            visible: !Services.WifiBridge.scanning && Services.WifiBridge.scannedNetworks.length === 0
            kind: "label"
            text: "No networks found."
        }
    }
}

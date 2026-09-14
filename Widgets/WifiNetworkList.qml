import QtQuick
import qs.Config as Config
import qs.Services as Services

// phiOS — Widgets/WifiNetworkList. docs/TODO.md: "clicking on the wifi
// icon should show the list of available wifi to connect. Same in the
// settings." Shared between Panels/BarPopout.qml's wifi card and
// Settings/sections/Connectivity.qml's Wi-Fi group — same reasoning as
// every other widget in this directory: one implementation, two callers,
// rather than the list/connect logic duplicated in both places.
//
// `active` controls when a scan is triggered: Settings' Connectivity
// section only exists while it's the loaded section (Settings/Settings.qml's
// Loader), so the default `true` fires a scan exactly once per visit there.
// Panels/BarPopout.qml's cards, by contrast, are all permanently
// instantiated behind a `visible:` binding (never destroyed/recreated), so
// that caller passes `active: root.which === "wifi"` explicitly — without
// it, `Component.onCompleted` would fire once at shell startup regardless
// of whether the wifi popout is ever opened.
//
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

        Row {
            width: parent.width
            spacing: root.gap
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                kind: "label"
                text: Services.WifiBridge.scanning
                    ? "Scanning…"
                    : (Services.WifiBridge.scannedNetworks.length + (Services.WifiBridge.scannedNetworks.length === 1 ? " network found" : " networks found"))
            }
            SmallButton {
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

        Repeater {
            model: Services.WifiBridge.scannedNetworks

            delegate: ListRow {
                width: col.width
                label: modelData.ssid
                value: modelData.connected
                    ? ("Connected · " + modelData.signal + "%")
                    : (modelData.known
                        ? ("Saved · " + modelData.signal + "%")
                        : (modelData.secured
                            ? ("Secured · " + modelData.signal + "%")
                            : ("Open · " + modelData.signal + "%")))
                // A secured network never joined before has no tap action
                // (see the file header) — the row still shows its status,
                // it just doesn't respond to a click.
                onActivated: {
                    if (modelData.connected) return
                    if (modelData.secured && !modelData.known) return
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

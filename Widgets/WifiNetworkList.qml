import QtQuick
import qs.Config as Config
import qs.Services as Services

// Scannable Wi-Fi network list (Settings/Connectivity). One implementation so
// list/connect logic is reusable. Active controls when scan is triggered;
// default true fires scan once per visit. WifiBridge owns scan/connect and
// nmcli calls. Secured networks this device never joined are not tappable
// (password would be world-readable via /proc/<pid>/cmdline).
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

        // Item for status left/button right; Row would pack all children snug.
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
                // Animated dots for visual feedback during scan.
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

        // Skeleton only on first scan; rescans keep showing results.
        Skeleton {
            width: parent.width
            visible: Services.WifiBridge.scanning && Services.WifiBridge.scannedNetworks.length === 0
            count: 3
        }

        Repeater {
            model: Services.WifiBridge.scannedNetworks

            delegate: ListRow {
                interactive: true
                // Thin: compact look; see ListRow.qml for why not the default.
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
                // Enabled reflects actionability; reads as inert when no action.
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

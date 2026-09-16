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

        // rework-status-bar.md Style item 9b: "the 'Refresh' button is not
        // aligned correctly (should be on the right side, instead of
        // close to the title)" — was a plain `Row` with a fixed `spacing`,
        // which packs every child snug against the previous one from the
        // left edge (Refresh included) rather than pushing the last one
        // to the far side. An `Item` with the status text/indicator
        // anchored left and the button anchored right gives the button a
        // real right-aligned position, same shape this file's own sibling
        // status-bar-overlay headers already use for "label left, control
        // right".
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
                // Style pass 2026-09-14: a real animated "still working" cue
                // (Widgets/Dots, promoted from the agent panel this pass) in
                // place of a static "Scanning…" that never visibly changed —
                // one more small instance of the same "trigger buttons don't
                // show loading states" gap, here on the row NEXT TO the
                // button rather than the button itself.
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

        // Style pass 2026-09-14 (docs/TODO.md: "a reusable loading-skeleton
        // placeholder for async lists"). Only for the FIRST scan (nothing
        // to show yet) — a rescan that already has a result list keeps
        // showing it while it refreshes (the Refresh button's own
        // `loading` already covers that case); replacing a real, useful
        // list with a skeleton on every rescan would be a regression, not
        // an improvement.
        Skeleton {
            width: parent.width
            visible: Services.WifiBridge.scanning && Services.WifiBridge.scannedNetworks.length === 0
            count: 3
        }

        Repeater {
            model: Services.WifiBridge.scannedNetworks

            delegate: ListRow {
                // User bug report, 2026-09-16: the earlier "thin" restyle
                // (rework-issues.md item 14) was built into ListRow's own
                // default look, so it leaked into every unrelated caller
                // (Settings nav, the agent panel, …) — now opt-in
                // (Widgets/ListRow.qml's own header). This is one of the
                // two real "status bar overlay device list" callers it was
                // actually reported against.
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
                // Style pass: a secured-never-joined or already-connected
                // row used to render fully interactive (hover wash, pointer
                // cursor) while `onActivated` silently did nothing — a
                // classic "looks clickable, isn't" trap. `enabled` now
                // reflects that directly: ListRow's own disabled dimming
                // and its hover/cursor handlers already key off `enabled`,
                // so an inert row now reads as inert.
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

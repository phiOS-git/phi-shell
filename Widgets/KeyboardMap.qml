import QtQuick
import qs.Config as Config

// phiOS — Widgets/KeyboardMap (Out-of-plan: settings-overhaul batch G). The
// per-key editor surface for Chroma's advanced mode: a plain rows×cols grid
// of cells, one per addressable matrix position, each showing its override
// colour (or the unset neutral). Clicking a cell selects it and emits
// keyPicked — Settings/sections/Devices.qml opens a Widgets/ColorPicker
// below and writes the result back through Services.Chroma.setKeyOverride.
//
// Deliberately a raw matrix, not a drawn keyboard: this shell has no
// verified keycap layout for the user's specific Razer Blade, and a wrong
// one would mislabel every key. The grid dimensions come from the device
// itself (Services.Chroma.matrixRows / matrixCols, from openrazer's
// getMatrixDimensions). It doubles as the coordinate-discovery tool — click
// a cell, see which physical key lights up, read off (row, col) for the
// battery power-key and notification function-row settings.
//
// Solid colour only — no lighting animation, per the user's directive.

Item {
    id: root

    property int rows: 6
    property int cols: 22
    property var overrides: ({})        // { "r,c": "#rrggbb" }
    property color baseColor: Config.Appearance.surface2
    property int selectedRow: -1
    property int selectedCol: -1

    signal keyPicked(int row, int col)

    readonly property real _gap: 3
    readonly property real _cellW: root.cols > 0
        ? Math.max(6, (root.width - (root.cols - 1) * _gap) / root.cols)
        : 0
    readonly property real _cellH: _cellW * 0.92

    implicitHeight: root.rows > 0
        ? root.rows * _cellH + (root.rows - 1) * _gap
        : 0

    Repeater {
        model: root.rows * root.cols

        Rectangle {
            id: cell
            required property int index
            readonly property int cellRow: Math.floor(index / root.cols)
            readonly property int cellCol: index % root.cols
            readonly property string key: cellRow + "," + cellCol
            readonly property var ov: root.overrides ? root.overrides[key] : undefined
            readonly property bool selected: root.selectedRow === cellRow && root.selectedCol === cellCol

            x: cellCol * (root._cellW + root._gap)
            y: cellRow * (root._cellH + root._gap)
            width: root._cellW
            height: root._cellH
            radius: Config.Appearance.radiusSmall

            color: cell.ov !== undefined && cell.ov !== null && String(cell.ov).length > 0
                ? String(cell.ov)
                : root.baseColor
            border.width: cell.selected ? Config.Appearance.borderWidthStrong : Config.Appearance.borderWidth
            border.color: cell.selected ? Config.Appearance.accent
                : (hover.hovered ? Config.Appearance.borderStrong : Config.Appearance.border)

            HoverHandler { id: hover }
            TapHandler {
                onTapped: {
                    root.selectedRow = cell.cellRow
                    root.selectedCol = cell.cellCol
                    root.keyPicked(cell.cellRow, cell.cellCol)
                }
            }

            // A faint dot marks a cell that carries an override, so a
            // near-base colour is still visibly "set".
            Rectangle {
                visible: cell.ov !== undefined && cell.ov !== null && String(cell.ov).length > 0
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 1
                width: 3; height: 3; radius: 1.5
                color: Config.Appearance.textPrimary
                opacity: 0.5
            }
        }
    }
}

import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets

// A read-only, interactive month grid — no event/CalDAV backend exists
// anywhere in this codebase. Clicking a day only highlights it locally;
// no event data is fabricated. Prev/next navigate the viewed month; today
// and the current selection are tracked independently so navigating away
// and back loses neither.

Widgets.OverlaySection {
    id: root

    property real chWidth: 0
    property int viewYear: 1970
    property int viewMonth: 0
    property int selectedYear: 1970
    property int selectedMonth: 0
    property int selectedDay: 1

    signal prevRequested()
    signal nextRequested()
    signal daySelected(int day)

    readonly property var _today: new Date()

    function _daysInMonth(y, m) { return new Date(y, m + 1, 0).getDate() }
    function _firstWeekday(y, m) { return new Date(y, m, 1).getDay() } // 0 = Sunday

    readonly property var _cells: {
        const dim = root._daysInMonth(root.viewYear, root.viewMonth)
        const lead = root._firstWeekday(root.viewYear, root.viewMonth)
        const cells = []
        for (let i = 0; i < lead; i++) cells.push({ day: 0 })
        for (let d = 1; d <= dim; d++) cells.push({ day: d })
        return cells
    }

    width: parent ? parent.width : 0

    Item {
        width: parent.width
        implicitHeight: Math.max(monthLabel.implicitHeight, monthNext.implicitHeight)

        Widgets.SmallButton {
            id: monthPrev
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            label: "‹"
            onClicked: root.prevRequested()
        }
        Widgets.StyledText {
            id: monthLabel
            anchors.centerIn: parent
            kind: "title"
            sizeStep: 1
            text: Qt.formatDateTime(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
        }
        Widgets.SmallButton {
            id: monthNext
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: "›"
            onClicked: root.nextRequested()
        }
    }

    Grid {
        width: parent.width
        columns: 7
        readonly property real cellSize: width / 7

        Repeater {
            model: ["S", "M", "T", "W", "T", "F", "S"]
            Widgets.StyledText {
                required property string modelData
                width: parent.cellSize
                height: root.chWidth * Config.Appearance.space4
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                kind: "label"; sizeStep: 0
                text: modelData
            }
        }

        Repeater {
            model: root._cells
            Item {
                id: dayCell
                required property var modelData
                width: parent.cellSize
                height: root.chWidth * Config.Appearance.space4

                readonly property bool isToday: dayCell.modelData.day > 0
                    && root.viewYear === root._today.getFullYear()
                    && root.viewMonth === root._today.getMonth()
                    && dayCell.modelData.day === root._today.getDate()
                readonly property bool isSelected: dayCell.modelData.day > 0
                    && root.viewYear === root.selectedYear
                    && root.viewMonth === root.selectedMonth
                    && dayCell.modelData.day === root.selectedDay

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) * 0.78
                    height: width
                    radius: Config.Appearance.radiusSmall
                    visible: dayCell.modelData.day > 0 && (dayCell.isSelected || dayCell.isToday)
                    color: dayCell.isSelected ? Config.Appearance.colorOpposite : "transparent"
                    border.width: (dayCell.isToday && !dayCell.isSelected) ? Config.Appearance.borderWidthStrong : 0
                    border.color: Config.Appearance.accent
                }
                Widgets.StyledText {
                    anchors.centerIn: parent
                    visible: dayCell.modelData.day > 0
                    mono: true
                    color: dayCell.isSelected ? Config.Appearance.colorMain : Config.Appearance.textPrimary
                    text: dayCell.modelData.day > 0 ? String(dayCell.modelData.day) : ""
                }
                HoverHandler {
                    enabled: dayCell.modelData.day > 0
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    enabled: dayCell.modelData.day > 0
                    onTapped: root.daySelected(dayCell.modelData.day)
                }
            }
        }
    }
}

import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// A pending pi dialog (`select` / `confirm` / `input` / `editor`,
// agent-panel-plan.md §5.3): an accent-bordered card so it reads as
// something that needs the user, not just another tool line.
// `view.readOnly` (the Code section's read-only timeline viewer) shows the
// question with no controls — a coding session's dialogs are answered in
// its own terminal, not from here.

Item {
    id: root

    property var row: null
    property var view: null

    readonly property var _dialog: {
        try { return JSON.parse((root.row && root.row.details) || "{}") } catch (e) { return {} }
    }
    readonly property var _options: root._dialog.options || []
    readonly property string _method: root._dialog.method || ""
    readonly property real _deadlineMs: root._dialog.deadline ? Date.parse(root._dialog.deadline) : 0

    // Date.now() in a binding would never re-evaluate on its own; the
    // Timer below advances this property instead, once a second, only
    // while the row is actually on screen.
    property real _now: Date.now()
    Timer {
        interval: 1000
        running: root.visible && root._deadlineMs > 0
        repeat: true
        onTriggered: root._now = Date.now()
    }
    readonly property int _remainingS: root._deadlineMs > 0 ? Math.max(0, Math.round((root._deadlineMs - root._now) / 1000)) : -1
    readonly property string _countdown: root._remainingS >= 0
        ? "answers itself in " + Math.floor(root._remainingS / 60) + ":" + String(root._remainingS % 60).padStart(2, "0")
        : ""

    width: parent ? parent.width : 0
    implicitHeight: panel.height
    height: implicitHeight

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width

    // Only ever called from an explicit button tap below, never from a
    // field's own commit/focus-out signal — a dialog answer must be a
    // deliberate action, not a side effect of the field losing focus.
    function _answer(payload) {
        if (root.view && root.row) Services.Agent.answerDialog(root.view.sessionId, root._dialog.id, payload)
    }

    Widgets.Panel {
        id: panel
        width: parent.width
        height: col.implicitHeight + padding * 2
        borderColorOverride: Config.Appearance.accent

        Column {
            id: col
            width: parent.width
            spacing: root.chWidth * Config.Appearance.space1

            Widgets.StyledText { kind: "label"; color: Config.Appearance.accent; text: "The agent is asking" }
            Widgets.StyledText { width: col.width; wrapMode: Text.Wrap; kind: "title"; text: root._dialog.title || "" }
            Widgets.StyledText { width: col.width; wrapMode: Text.Wrap; text: root._dialog.message || "" }

            Column {
                visible: !(root.view && root.view.readOnly)
                width: col.width
                spacing: root.chWidth * Config.Appearance.space1

                Flow {
                    visible: root._method === "select"
                    width: col.width
                    spacing: root.chWidth * Config.Appearance.space1
                    Repeater {
                        model: root._options
                        delegate: Widgets.StyledButton {
                            required property var modelData
                            label: modelData
                            onClicked: root._answer({ value: modelData })
                        }
                    }
                }

                Row {
                    visible: root._method === "confirm"
                    spacing: root.chWidth * Config.Appearance.space1
                    Widgets.StyledButton { label: "Yes"; onClicked: root._answer({ confirmed: true }) }
                    Widgets.StyledButton { label: "No"; onClicked: root._answer({ confirmed: false }) }
                }

                Row {
                    visible: root._method === "input"
                    width: col.width
                    spacing: root.chWidth * Config.Appearance.space1
                    Widgets.TextField {
                        id: inputField
                        width: col.width - sendBtn.implicitWidth - parent.spacing
                        placeholder: root._dialog.placeholder || ""
                        text: root._dialog.prefill || ""
                    }
                    Widgets.StyledButton { id: sendBtn; label: "Send"; onClicked: root._answer({ value: inputField.text }) }
                }

                Column {
                    visible: root._method === "editor"
                    width: col.width
                    spacing: root.chWidth * Config.Appearance.space1

                    Widgets.Panel {
                        width: col.width
                        height: root.chWidth * Config.Appearance.space6 * 4
                        Flickable {
                            anchors.fill: parent
                            clip: true
                            contentWidth: width
                            contentHeight: editor.implicitHeight

                            TextEdit {
                                id: editor
                                width: parent.width
                                wrapMode: TextEdit.Wrap
                                text: root._dialog.prefill || ""
                                font.family: Config.Appearance.fontUi
                                font.pixelSize: Config.Appearance.fontSize1
                                color: Config.Appearance.textPrimary
                                selectionColor: Config.Appearance.selectionBackground
                                selectedTextColor: Config.Appearance.selectionText
                                selectByMouse: true
                            }
                        }
                    }
                    Widgets.StyledButton { label: "Send"; onClicked: root._answer({ value: editor.text }) }
                }

                Row {
                    width: col.width
                    spacing: root.chWidth * Config.Appearance.space1
                    Widgets.SmallButton { label: "Dismiss"; onClicked: root._answer({ cancelled: true }) }
                    Widgets.StyledText {
                        visible: root._countdown.length > 0
                        kind: "label"
                        sizeStep: 0
                        color: Config.Appearance.textFaint
                        text: root._countdown
                    }
                }
            }

            Widgets.StyledText {
                visible: root.view && root.view.readOnly
                kind: "label"
                color: Config.Appearance.textFaint
                text: "Answer it in the terminal"
            }
        }
    }
}

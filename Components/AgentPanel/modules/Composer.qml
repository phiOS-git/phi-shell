import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// The message composer (agent-panel-plan.md §3.1). Idle: Enter sends. While a
// turn runs: Enter queues per the busyEnter pref (follow-up or steer) and
// Alt+Enter does the other; Stop (or Ctrl+.) clears the queue back into the
// field and aborts. Shift+Enter is a new line, Up in an empty field recalls
// the last message, "/" opens pi's commands, Ctrl+V also attaches a
// clipboard image. Text is kept per chat as a draft while the shell runs, and
// nothing typed is lost on a failed send.
//
// The pickers (profile, model, thinking) open upwards: the composer sits at
// the bottom of a clipped area.

Column {
    id: root

    signal blurred()

    readonly property var agent: Services.Agent
    readonly property string sid: root.agent.currentSessionId
    readonly property var st: root.agent.currentState || ({})
    readonly property bool busy: root.agent.processing
    readonly property var attached: root.agent.attachments[root.sid] || []
    readonly property var queued: {
        const q = root.agent.queue || {}
        return ((q.steering || []).map((t) => ({ kind: "steer", text: t })))
            .concat((q.followUp || []).map((t) => ({ kind: "then", text: t })))
    }

    function focusField() { field.forceActiveFocus() }
    function insertText(t) {
        field.forceActiveFocus()
        field.insert(field.cursorPosition, t)
    }

    function doSend(mode) {
        if (root.paletteOpen && mode === "") { root.pickCommand(root.paletteIndex); return }
        const text = field.text
        if (text.trim().length === 0 && root.attached.length === 0) return
        if (root.agent.creating) return
        root.agent.send(text, mode)
        field.text = ""
    }

    function lastUserText() {
        const rows = root.agent.rows
        for (let i = rows.count - 1; i >= 0; i--) {
            const r = rows.get(i)
            if (r.kind === "user") return r.text
        }
        return ""
    }

    // --- drafts ----------------------------------------------------------
    property bool _loadingDraft: false
    function _loadDraft() {
        root._loadingDraft = true
        field.text = root.agent.drafts[root.sid] || ""
        field.cursorPosition = field.text.length
        root._loadingDraft = false
    }
    onSidChanged: root._loadDraft()
    Component.onCompleted: root._loadDraft()
    Timer { id: draftSave; interval: 400; onTriggered: root.agent.setDraft(root.sid, field.text) }
    Connections {
        target: root.agent
        function onQueueRestored(text) {
            field.text = field.text.length > 0 ? text + "\n\n" + field.text : text
            field.forceActiveFocus()
        }
        function onSendFailed(text) { if (field.text.length === 0) field.text = text }
    }

    // --- slash-command palette -------------------------------------------
    readonly property string _slash: {
        const t = field.text
        return (t.startsWith("/") && t.indexOf(" ") < 0 && t.indexOf("\n") < 0) ? t.slice(1).toLowerCase() : ""
    }
    readonly property var matches: (field.text.startsWith("/") && field.text.indexOf(" ") < 0)
        ? (root.agent.commands || []).filter((c) => c.name.toLowerCase().startsWith(root._slash)).slice(0, 8)
        : []
    readonly property bool paletteOpen: root.matches.length > 0 && field.activeFocus
    property int paletteIndex: 0
    onMatchesChanged: root.paletteIndex = 0
    function pickCommand(i) {
        const c = root.matches[i]
        if (!c) return
        field.text = "/" + c.name + " "
        field.cursorPosition = field.text.length
    }

    // --- picker state (one open at a time) ----------------------------------
    property string pickerOpen: ""   // "" | "profile" | "model" | "thinking"
    readonly property var modelRefs: (root.agent.models || []).map((m) => m.provider + "/" + m.id)
    readonly property string currentModelRef: (root.st.model && root.st.model.id)
        ? root.st.model.provider + "/" + root.st.model.id : root.agent.pendingModel
    readonly property var thinkingLevels: (root.st.thinkingLevels && root.st.thinkingLevels.length > 0)
        ? root.st.thinkingLevels : ["off", "minimal", "low", "medium", "high"]
    readonly property string currentThinking: root.st.thinkingLevel || root.agent.pendingThinking

    property bool pathOpen: false

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2
    readonly property real tight: chWidth * Config.Appearance.space1

    spacing: root.tight
    enabled: root.agent.available

    // --- command palette ------------------------------------------------------
    Widgets.Panel {
        width: parent.width
        visible: root.paletteOpen
        height: paletteCol.implicitHeight + padding * 2
        Column {
            id: paletteCol
            width: parent.width
            Repeater {
                model: root.matches
                delegate: Widgets.ListRow {
                    required property var modelData
                    required property int index
                    width: paletteCol.width
                    interactive: true
                    thin: true
                    active: index === root.paletteIndex
                    label: "/" + modelData.name
                    value: modelData.description || modelData.source || ""
                    onActivated: { root.pickCommand(index); field.forceActiveFocus() }
                }
            }
        }
    }

    // --- queue and attachments ------------------------------------------------
    Flow {
        width: parent.width
        spacing: root.tight
        visible: root.queued.length > 0 || root.attached.length > 0

        Repeater {
            model: root.queued
            delegate: chip
        }
        Widgets.SmallButton {
            visible: root.queued.length > 0
            label: "Clear queue"
            onClicked: root.agent.clearQueue()
        }
        Repeater {
            model: root.attached.map((p) => ({ kind: "image", text: p.split("/").pop(), path: p }))
            delegate: chip
        }
    }
    Component {
        id: chip
        Rectangle {
            id: chipItem
            required property var modelData
            width: Math.min(chipRow.implicitWidth + root.chWidth * 1.5, root.width)
            height: chipRow.implicitHeight + root.chWidth * 0.6
            radius: Config.Appearance.radiusPill
            color: Config.Appearance.surface2
            border.width: Config.Appearance.borderWidth
            border.color: Config.Appearance.border
            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: root.chWidth * 0.5
                Widgets.StyledText { kind: "label"; sizeStep: 0; mono: true; text: chipItem.modelData.kind + ":" }
                Widgets.StyledText {
                    width: Math.min(implicitWidth, root.width * 0.5)
                    elide: Text.ElideRight
                    sizeStep: 0
                    text: chipItem.modelData.text.replace(/\s+/g, " ")
                }
                Widgets.StyledText {
                    visible: chipItem.modelData.kind === "image"
                    kind: "label"
                    sizeStep: 0
                    text: "×"
                    TapHandler { onTapped: root.agent.removeAttachment(chipItem.modelData.path) }
                }
            }
        }
    }

    Widgets.TextField {
        visible: root.pathOpen
        width: parent.width
        placeholder: "/absolute/path/to/image.png — Enter attaches"
        onCommitted: (t) => { root.agent.addAttachment(t); text = ""; root.pathOpen = false; field.forceActiveFocus() }
        onEscaped: { root.pathOpen = false; field.forceActiveFocus() }
    }

    // --- field ------------------------------------------------------------
    Widgets.Panel {
        width: parent.width
        height: fieldScroll.height + padding * 2
        active: field.activeFocus

        Flickable {
            id: fieldScroll
            readonly property real lineHeight: field.font.pixelSize * 1.45
            width: parent.width
            height: Math.max(lineHeight, Math.min(field.implicitHeight, lineHeight * 8))
            contentWidth: width
            contentHeight: field.implicitHeight
            clip: true
            interactive: contentHeight > height
            onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

            TextEdit {
                id: field
                width: fieldScroll.width
                wrapMode: TextEdit.Wrap
                font.family: Config.Appearance.fontUi
                font.pixelSize: Config.Appearance.fontSize1
                color: Config.Appearance.textPrimary
                selectionColor: Config.Appearance.selectionBackground
                selectedTextColor: Config.Appearance.selectionText
                selectByMouse: true
                readOnly: !root.agent.available

                onTextChanged: if (!root._loadingDraft) draftSave.restart()

                Keys.onPressed: (event) => {
                    const ctrl = event.modifiers & Qt.ControlModifier
                    const alt = event.modifiers & Qt.AltModifier
                    const shift = event.modifiers & Qt.ShiftModifier
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (shift) return
                        root.doSend(alt ? "alt" : "")
                        event.accepted = true
                    } else if (root.paletteOpen && (event.key === Qt.Key_Down || event.key === Qt.Key_Up)) {
                        const n = root.matches.length
                        root.paletteIndex = (root.paletteIndex + (event.key === Qt.Key_Down ? 1 : n - 1)) % n
                        event.accepted = true
                    } else if (root.paletteOpen && event.key === Qt.Key_Tab) {
                        root.pickCommand(root.paletteIndex)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Up && field.text.length === 0) {
                        field.text = root.lastUserText()
                        field.cursorPosition = field.text.length
                        event.accepted = true
                    } else if (ctrl && event.key === Qt.Key_V) {
                        // Attach a clipboard image when there is one; the
                        // ordinary text paste still happens.
                        root.agent.pasteClipboardImage()
                    } else if (ctrl && event.key === Qt.Key_Period) {
                        root.agent.stop()
                        event.accepted = true
                    }
                }
                Keys.onEscapePressed: {
                    if (root.pickerOpen.length > 0) { root.pickerOpen = ""; return }
                    field.focus = false
                    root.blurred()
                }

                Widgets.StyledText {
                    anchors.fill: parent
                    kind: "label"
                    visible: field.text.length === 0
                    elide: Text.ElideRight
                    text: !root.agent.available ? "The agent is offline."
                        : root.busy ? (Config.AgentPrefs.busyEnter === "steer"
                            ? "Steer the running turn — Alt+Enter queues a follow-up"
                            : "Queue a follow-up — Alt+Enter steers the running turn")
                        : "Message the agent…"
                }
            }
        }
    }

    // --- controls ------------------------------------------------------------
    Item {
        width: parent.width
        height: Math.max(leftControls.implicitHeight, rightControls.implicitHeight)

        Row {
            id: leftControls
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.tight

            Picker {
                key: "profile"
                visible: root.sid.length === 0
                label: root.agent.currentProfile
                options: root.agent.profiles || []
                current: root.agent.currentProfile
                onPicked: (v) => { root.agent.newChatProfile = v; root.agent.refreshModels(v) }
            }
            Picker {
                key: "model"
                visible: root.modelRefs.length > 0 || root.currentModelRef.length > 0
                label: root.currentModelRef.length > 0 ? root.currentModelRef.split("/").slice(1).join("/") : "model"
                options: root.modelRefs
                current: root.currentModelRef
                onPicked: (v) => root.agent.setModel(v)
            }
            Picker {
                key: "thinking"
                visible: root.agent.rich
                label: "think: " + (root.currentThinking || "default")
                options: root.thinkingLevels
                current: root.currentThinking
                onPicked: (v) => root.agent.setThinking(v)
            }
            Widgets.SmallButton {
                visible: root.agent.rich
                label: "Image…"
                active: root.pathOpen
                onClicked: root.pathOpen = !root.pathOpen
            }
        }

        Row {
            id: rightControls
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.tight
            Widgets.StyledButton {
                visible: root.busy
                label: "Stop"
                invalid: true
                onClicked: root.agent.stop()
            }
            Widgets.StyledButton {
                label: root.busy ? "Queue" : "Send"
                loading: root.agent.creating
                active: field.text.trim().length > 0 || root.attached.length > 0
                onClicked: root.doSend("")
            }
        }
    }

    // A chip that opens its option list upwards, above the controls row.
    component Picker: Widgets.SmallButton {
        id: picker
        property string key: ""
        property var options: []
        property string current: ""
        signal picked(string value)
        active: root.pickerOpen === picker.key
        onClicked: root.pickerOpen = (root.pickerOpen === picker.key ? "" : picker.key)

        Widgets.Panel {
            visible: root.pickerOpen === picker.key && picker.options.length > 0
            z: 20
            x: 0
            y: -height - root.tight
            width: Math.max(picker.width, root.chWidth * 28 + padding * 2)
            height: pickCol.implicitHeight + padding * 2
            Column {
                id: pickCol
                Repeater {
                    model: picker.options
                    delegate: Widgets.ListRow {
                        required property var modelData
                        width: root.chWidth * 28
                        interactive: true
                        thin: true
                        active: modelData === picker.current
                        label: modelData
                        onActivated: { picker.picked(modelData); root.pickerOpen = "" }
                    }
                }
            }
        }
    }
}

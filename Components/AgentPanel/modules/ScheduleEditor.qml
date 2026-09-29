import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// A scheduled-prompt job form, shared by "New scheduled prompt" and each
// job's "Edit" (plan §5.7). Fields are read/written by id rather than
// mirrored into a property per field, except for the
// three fields that gate which other fields are visible (`when` kind,
// `target` mode, the daily weekday set), which need a real property to
// drive that visibility.

Item {
    id: root
    property var job: null       // null = new job
    signal done()

    readonly property var agent: Services.Agent

    TextMetrics { id: ch; font.family: Config.Appearance.fontMono; font.pixelSize: Config.Appearance.fontSize1; text: "0" }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2
    readonly property real tightGap: Math.round(chWidth * Config.Appearance.space1 * 0.5)

    property string whenKind: "once"        // "once" | "daily" | "interval"
    property var dailyWeekdays: []          // 1=Mon..7=Sun, empty = every day
    property string targetMode: "new"       // "new" | "session"
    property string errorText: ""
    property bool saving: false

    readonly property var weekdayLabels: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    readonly property var projectNames: (root.agent.projects || []).map((p) => p.name)
    readonly property var sessionOptions: (root.agent.sessions || []).map((s) => ({ id: s.id, label: s.title || s.id }))

    function sessionLabel(id) {
        for (var i = 0; i < root.sessionOptions.length; i++) if (root.sessionOptions[i].id === id) return root.sessionOptions[i].label
        return id
    }
    function sessionIdForLabel(label) {
        for (var i = 0; i < root.sessionOptions.length; i++) if (root.sessionOptions[i].label === label) return root.sessionOptions[i].id
        return ""
    }

    function fmtLocal(d) {
        function p2(n) { return (n < 10 ? "0" : "") + n }
        return d.getFullYear() + "-" + p2(d.getMonth() + 1) + "-" + p2(d.getDate()) + " " + p2(d.getHours()) + ":" + p2(d.getMinutes())
    }
    function parseOnce(text) {
        var m = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})$/.exec((text || "").trim())
        if (!m) return null
        var d = new Date(parseInt(m[1]), parseInt(m[2]) - 1, parseInt(m[3]), parseInt(m[4]), parseInt(m[5]), 0, 0)
        return isNaN(d.getTime()) ? null : d
    }

    function load(j) {
        root.errorText = ""
        if (j) {
            titleField.text = j.title || ""
            promptEdit.text = j.prompt || ""
            profileSelect.value = j.profile || "general"
            projectSelect.value = j.project || "(none)"
            var w = j.when || {}
            root.whenKind = w.kind || "once"
            var d = (w.kind === "once") ? new Date(w.at || "") : null
            onceField.text = (d && !isNaN(d.getTime())) ? root.fmtLocal(d) : ""
            dailyTimeField.text = w.time || "09:00"
            root.dailyWeekdays = (w.weekdays || []).slice()
            intervalField.value = w.minutes || 60
            var t = j.target || "new"
            if (t.indexOf("session:") === 0) { root.targetMode = "session"; sessionSelect.value = root.sessionLabel(t.slice(8)) }
            else { root.targetMode = "new"; sessionSelect.value = "" }
            costField.value = j.maxCost || 0
            enabledToggle.checked = j.enabled !== false
        } else {
            titleField.text = ""
            promptEdit.text = ""
            profileSelect.value = "general"
            projectSelect.value = "(none)"
            root.whenKind = "once"
            onceField.text = ""
            dailyTimeField.text = "09:00"
            root.dailyWeekdays = []
            intervalField.value = 60
            root.targetMode = "new"
            sessionSelect.value = ""
            costField.value = 0
            enabledToggle.checked = true
        }
    }
    Component.onCompleted: root.load(root.job)
    onJobChanged: root.load(root.job)

    function buildWhen() {
        if (root.whenKind === "once") {
            var d = root.parseOnce(onceField.text)
            return { kind: "once", at: d.toISOString() }
        }
        if (root.whenKind === "daily")
            return { kind: "daily", time: dailyTimeField.text.trim(), weekdays: root.dailyWeekdays.slice().sort((a, b) => a - b) }
        return { kind: "interval", minutes: intervalField.value }
    }
    function validate() {
        if (titleField.text.trim().length === 0) return "Title is required."
        if (promptEdit.text.trim().length === 0) return "Prompt is required."
        if (root.whenKind === "once" && !root.parseOnce(onceField.text)) return "Enter the date and time as YYYY-MM-DD HH:MM."
        if (root.whenKind === "daily" && !/^([01]\d|2[0-3]):([0-5]\d)$/.test(dailyTimeField.text.trim())) return "Enter the time as HH:MM."
        if (root.targetMode === "session" && root.sessionIdForLabel(sessionSelect.value).length === 0) return "Choose a chat to continue."
        return ""
    }
    function save() {
        var err = root.validate()
        if (err.length > 0) { root.errorText = err; return }
        var obj = {
            title: titleField.text.trim(),
            prompt: promptEdit.text,
            profile: profileSelect.value,
            project: projectSelect.value === "(none)" ? "" : projectSelect.value,
            when: root.buildWhen(),
            target: root.targetMode === "session" ? ("session:" + root.sessionIdForLabel(sessionSelect.value)) : "new",
            maxCost: costField.value,
            enabled: enabledToggle.checked
        }
        if (root.job && root.job.id) obj.id = root.job.id
        root.errorText = ""
        root.saving = true
        root.agent.saveJob(obj, function (ok, res) {
            root.saving = false
            if (ok) root.done()
            else root.errorText = (typeof res === "string" && res.length > 0) ? res : "Could not save the scheduled prompt."
        })
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: form.implicitHeight
        clip: true

        Column {
            id: form
            width: parent.width
            spacing: root.gap

            Widgets.StyledText { kind: "label"; sizeStep: 0; text: "Title" }
            Widgets.TextField { id: titleField; width: parent.width; mono: false; placeholder: "What this prompt does" }

            Widgets.StyledText { kind: "label"; sizeStep: 0; text: "Prompt" }
            Widgets.Panel {
                width: parent.width
                height: root.chWidth * 10
                Flickable {
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: promptEdit.implicitHeight
                    clip: true
                    TextEdit {
                        id: promptEdit
                        width: parent.width
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        font.family: Config.Appearance.fontUi
                        font.pixelSize: Config.Appearance.fontSize1
                        color: Config.Appearance.textPrimary
                        selectionColor: Config.Appearance.selectionBackground
                        selectedTextColor: Config.Appearance.selectionText
                        Widgets.StyledText {
                            anchors.fill: parent
                            kind: "label"
                            text: "What should the agent do…"
                            visible: promptEdit.text.length === 0
                        }
                    }
                }
            }

            Row {
                width: parent.width
                spacing: root.gap
                Column {
                    width: (parent.width - root.gap) / 2
                    spacing: root.tightGap
                    Widgets.StyledText { kind: "label"; sizeStep: 0; text: "Profile" }
                    Widgets.Select {
                        id: profileSelect
                        width: parent.width
                        options: ["general", "academic"]
                        value: "general"
                        onActivated: (v) => profileSelect.value = v
                    }
                }
                Column {
                    width: (parent.width - root.gap) / 2
                    spacing: root.tightGap
                    Widgets.StyledText { kind: "label"; sizeStep: 0; text: "Project" }
                    Widgets.Select {
                        id: projectSelect
                        width: parent.width
                        options: ["(none)"].concat(root.projectNames)
                        value: "(none)"
                        onActivated: (v) => projectSelect.value = v
                    }
                }
            }

            Widgets.Separator { width: parent.width }

            Widgets.StyledText { kind: "label"; sizeStep: 0; text: "When" }
            Widgets.Select {
                width: parent.width
                options: ["Once", "Daily", "Every N minutes"]
                value: root.whenKind === "once" ? "Once" : (root.whenKind === "daily" ? "Daily" : "Every N minutes")
                onActivated: (v) => root.whenKind = v === "Once" ? "once" : (v === "Daily" ? "daily" : "interval")
            }

            Widgets.TextField {
                id: onceField
                visible: root.whenKind === "once"
                width: parent.width
                placeholder: "YYYY-MM-DD HH:MM"
                invalid: text.length > 0 && !root.parseOnce(text)
            }

            Column {
                visible: root.whenKind === "daily"
                width: parent.width
                spacing: root.tightGap
                Widgets.TextField {
                    id: dailyTimeField
                    width: parent.width
                    placeholder: "HH:MM"
                    invalid: text.length > 0 && !/^([01]\d|2[0-3]):([0-5]\d)$/.test(text.trim())
                }
                Row {
                    spacing: root.gap
                    Repeater {
                        model: 7
                        delegate: Widgets.SmallButton {
                            required property int index
                            label: root.weekdayLabels[index]
                            active: root.dailyWeekdays.indexOf(index + 1) >= 0
                            onClicked: {
                                var d = root.dailyWeekdays.slice()
                                var v = index + 1
                                var pos = d.indexOf(v)
                                if (pos >= 0) d.splice(pos, 1); else d.push(v)
                                root.dailyWeekdays = d
                            }
                        }
                    }
                }
                Widgets.StyledText { kind: "label"; sizeStep: 0; text: "No day selected runs every day." }
            }

            Widgets.NumberField {
                id: intervalField
                visible: root.whenKind === "interval"
                from: 5
                to: 10080
                step: 5
                decimals: 0
                suffix: " min"
            }

            Widgets.Separator { width: parent.width }

            Widgets.StyledText { kind: "label"; sizeStep: 0; text: "Target" }
            Widgets.Select {
                width: parent.width
                options: ["New chat each run", "Continue one chat"]
                value: root.targetMode === "session" ? "Continue one chat" : "New chat each run"
                onActivated: (v) => root.targetMode = v === "Continue one chat" ? "session" : "new"
            }
            Widgets.Select {
                id: sessionSelect
                visible: root.targetMode === "session"
                width: parent.width
                options: root.sessionOptions.map((o) => o.label)
                placeholder: "Choose a chat…"
                onActivated: (v) => sessionSelect.value = v
            }

            Widgets.Separator { width: parent.width }

            Row {
                spacing: root.gap * 2
                Column {
                    spacing: root.tightGap
                    Widgets.StyledText { kind: "label"; sizeStep: 0; text: "Max cost per run" }
                    Widgets.NumberField { id: costField; from: 0; to: 100; step: 0.5; decimals: 2; suffix: " USD" }
                }
                Column {
                    spacing: root.tightGap
                    Widgets.StyledText { kind: "label"; sizeStep: 0; text: "Enabled" }
                    Widgets.Toggle { id: enabledToggle; checked: true; onToggled: (v) => enabledToggle.checked = v }
                }
            }

            Widgets.StyledText {
                visible: root.errorText.length > 0
                width: parent.width
                wrapMode: Text.WordWrap
                tone: "error"
                text: root.errorText
            }

            Row {
                spacing: root.gap
                Widgets.StyledButton { label: "Save"; loading: root.saving; onClicked: root.save() }
                Widgets.StyledButton { label: "Cancel"; onClicked: root.done() }
            }
        }
    }
}

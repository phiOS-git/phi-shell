import QtQuick
import Quickshell.Io
import qs.Config as Config
import qs.Widgets as Widgets
import "../modules" as Modules

// What phiOS declares as non-official software (profiles/*/external.txt,
// tiers TC/T2/T3/T4) and what `phi pkg audit` finds when it checks that
// declaration against reality. Three groups:
// - Audit: how many entries are declared, how many findings the last audit
//   produced, and the four fingerprint roots (`phi pkg audit --json`) with
//   their changed state. "Re-run audit" and "Accept" (per root, `phi pkg
//   accept <root>`) are the only actions this section performs.
// - Packages: one collapsible list per manager. phi / pacman / AUR come
//   from `phi pkg list --json` (bucketed by category); AppImage lists
//   ~/Applications (`phi pkg list --manager appimage --json`); external
//   (TC/T2/T3/T4) comes from `phi pkg list --manager external --json` and
//   shows each entry's tier and audit status instead of a version; npm and
//   flatpak stay labelled placeholders until their listers land.
// - Findings: the audit's Findings, grouped by check (drift / leak /
//   integrity) so the three read differently rather than as one flat list.
//
// The panel may perform non-interactive, unprivileged actions. It never
// runs an interactive privileged transaction: `pacman -Syu` and `phi
// update` need a TTY for conflict and provider prompts, so they stay in a
// terminal the user runs themselves. This is not a new precedent — `phi
// vpn` and `phi firewall` are already driven from Settings through `sudo
// -n` drop-ins; the boundary was never "the GUI never acts", only "never an
// interactive privileged one".

Column {
    id: root
    width: parent ? parent.width : 0
    spacing: Config.Appearance.space3 * chWidth

    TextMetrics {
        id: ch
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: ch.width
    readonly property real gap: Config.Appearance.space2 * chWidth

    readonly property var rootNames: ["applications", "opt", "flatpak", "local-bin"]

    property var allEntries: []
    property var appimages: []
    property var externalEntries: []
    property var auditData: ({ Entries: [], Problems: [], Findings: [], Roots: [] })
    property bool auditing: false
    property bool auditLoaded: false
    property string acceptingRoot: ""
    property string acceptError: ""

    readonly property int _declaredCount: (root.auditData.Entries || []).length
    readonly property int _findingsCount: (root.auditData.Findings || []).length
    readonly property var _problems: root.auditData.Problems || []

    function refresh() {
        listProc.running = true
        appimageProc.running = true
        externalProc.running = true
        root.runAudit()
    }

    function runAudit() {
        root.auditing = true
        auditProc.running = true
    }

    function acceptRoot(name) {
        root.acceptError = ""
        root.acceptingRoot = name
        acceptProc.command = ["phi", "pkg", "accept", name]
        acceptProc.running = true
    }

    Component.onCompleted: refresh()

    function _entriesFor(cat) {
        return (root.allEntries || []).filter((e) => e.Category === cat)
    }

    function _rootInfo(name) {
        var roots = root.auditData.Roots || []
        for (var i = 0; i < roots.length; i++) {
            if (roots[i].Root === name) return roots[i]
        }
        return null
    }

    function _rootTitle(name) {
        switch (name) {
        case "applications": return "Applications"
        case "opt": return "Opt"
        case "flatpak": return "Flatpak"
        case "local-bin": return "Local bin"
        }
        return name
    }

    function _findingsFor(check) {
        return (root.auditData.Findings || []).filter((f) => f.Check === check)
    }

    // "" reads as textMuted (StyledText's default label colour) — used for
    // a tier, which is a classification, not a pass/fail signal.
    function _statusTone(status) {
        switch (status) {
        case "ok": return "success"
        case "unverified": return "info"
        case "missing": return "warn"
        case "changed": return "error"
        }
        return ""
    }

    function _kindTone(kind) {
        switch (kind) {
        case "undeclared": return "error"
        case "leak": return "error"
        case "checksum": return "error"
        case "missing": return "warn"
        case "changed": return "warn"
        }
        return ""
    }

    Process {
        id: listProc
        command: ["phi", "pkg", "list", "--json"]
        onExited: listProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.allEntries = JSON.parse(this.text) || [] }
                catch (e) { root.allEntries = [] }
            }
        }
    }
    Process {
        id: appimageProc
        command: ["phi", "pkg", "list", "--manager", "appimage", "--json"]
        onExited: appimageProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var l = JSON.parse(this.text)
                    root.appimages = (l && l.Entries) ? l.Entries : []
                } catch (e) { root.appimages = [] }
            }
        }
    }
    Process {
        id: externalProc
        command: ["phi", "pkg", "list", "--manager", "external", "--json"]
        onExited: externalProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var l = JSON.parse(this.text)
                    root.externalEntries = (l && l.Entries) ? l.Entries : []
                } catch (e) { root.externalEntries = [] }
            }
        }
    }
    // Exit code is non-zero whenever Findings is non-empty — that's the
    // command's normal way of signalling "there is something to look at",
    // not a failure, so the output is read regardless of exit status.
    // Problems/Findings can come back JSON `null` rather than `[]`, so every
    // read of them goes through `|| []` (see _findingsFor, _problems above).
    Process {
        id: auditProc
        command: ["phi", "pkg", "audit", "--json"]
        onExited: auditProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text) || {}
                    d.Entries = d.Entries || []
                    d.Problems = d.Problems || []
                    d.Findings = d.Findings || []
                    d.Roots = d.Roots || []
                    root.auditData = d
                } catch (e) {
                    root.auditData = { Entries: [], Problems: [], Findings: [], Roots: [] }
                }
                root.auditLoaded = true
                root.auditing = false
            }
        }
    }
    // `phi pkg accept <root>` is non-interactive and unprivileged — a real
    // exit code, unlike the audit above, so failure is reported rather than
    // silently re-running the audit on top of it.
    Process {
        id: acceptProc
        onExited: (exitCode) => {
            acceptProc.running = false
            if (exitCode === 0) {
                root.acceptingRoot = ""
                root.runAudit()
            } else {
                root.acceptError = "phi pkg accept " + root.acceptingRoot + " failed (exit " + exitCode + ")."
                root.acceptingRoot = ""
            }
        }
    }

    // --- one manager's collapsible list -----------------------------
    component ManagerBlock: Widgets.Accordion {
        id: mb
        property var entries: []
        property string placeholder: ""
        // External (TC/T2/T3/T4) entries carry a tier and an audit status
        // instead of a version — this swaps the row's version text for
        // those two instead. Default false keeps every other manager's row
        // exactly the plain Widgets.ListRow it always was.
        property bool tierStatus: false
        title: "…"
        width: parent ? parent.width : 0

        Repeater {
            model: mb.entries
            Widgets.ListRow {
                required property var modelData
                visible: !mb.tierStatus
                width: mb.width
                label: modelData.Name
                value: modelData.Version || ""
            }
        }
        Repeater {
            model: mb.tierStatus ? mb.entries : []
            Item {
                required property var modelData
                width: mb.width
                implicitHeight: Math.max(nameText.implicitHeight, statusRow.implicitHeight)
                    + root.chWidth * Config.Appearance.space1

                Widgets.StyledText {
                    id: nameText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: statusRow.left
                    anchors.rightMargin: root.gap
                    elide: Text.ElideRight
                    text: modelData.Name
                }
                Row {
                    id: statusRow
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.gap
                    Widgets.StyledText { kind: "label"; sizeStep: 0; mono: true; text: modelData.Tier || "" }
                    Widgets.StyledText {
                        kind: "label"; sizeStep: 0
                        tone: root._statusTone(modelData.Status)
                        text: modelData.Status || ""
                    }
                }
            }
        }
        Widgets.StyledText {
            width: mb.width
            visible: mb.entries.length === 0
            wrapMode: Text.WordWrap
            kind: "label"; sizeStep: 0
            text: mb.placeholder.length > 0 ? mb.placeholder : "None."
        }
    }

    // --- one Findings check group ------------------------------------
    component FindingGroup: Widgets.Accordion {
        id: fg
        property var findings: []
        // Seeded open when there is something to see — Widgets/Accordion.qml
        // treats `expanded` as plain view state the caller may seed; a tap
        // still overrides it from then on.
        expanded: fg.findings.length > 0
        title: "…"
        width: parent ? parent.width : 0

        Repeater {
            model: fg.findings
            Column {
                required property var modelData
                width: fg.width
                spacing: root.chWidth * Config.Appearance.space1 * 0.5

                Row {
                    spacing: root.gap
                    Widgets.StyledText { text: modelData.Name || "(unnamed)" }
                    Widgets.StyledText {
                        kind: "label"; sizeStep: 0
                        tone: root._kindTone(modelData.Kind)
                        text: modelData.Kind || ""
                    }
                }
                Widgets.StyledText {
                    visible: (modelData.Detail || "").length > 0
                    width: fg.width
                    wrapMode: Text.WordWrap
                    kind: "label"; sizeStep: 0
                    text: modelData.Detail || ""
                }
            }
        }
        Widgets.StyledText {
            width: fg.width
            visible: fg.findings.length === 0
            kind: "label"; sizeStep: 0
            text: "None."
        }
    }

    // ================================================================
    // Audit
    // ================================================================
    Modules.SettingsGroup {
        title: "Audit"
        optionId: "packages.audit"
        caption: "`phi pkg audit --json` checks profiles/*/external.txt against installed reality across four fingerprint roots. Findings stay below until you act on them."

        Widgets.Skeleton {
            width: parent ? parent.width : 0
            visible: root.auditing && !root.auditLoaded
            count: 3
        }

        Modules.SettingsRow {
            title: "Declared entries"
            description: "TC/T2/T3/T4 lines across profiles/*/external.txt."
            Widgets.StyledText { text: String(root._declaredCount) }
        }

        Modules.SettingsRow {
            title: "Findings"
            description: root._findingsCount > 0
                ? "Undeclared, leaked, missing or changed entries — see the Findings group below."
                : "Nothing to review."
            Widgets.StyledText {
                tone: root._findingsCount > 0 ? "warn" : "success"
                text: root._findingsCount > 0 ? String(root._findingsCount) : "None"
            }
        }

        Repeater {
            model: root.rootNames
            Modules.SettingsRow {
                id: rootRow
                required property string modelData
                readonly property var info: root._rootInfo(rootRow.modelData)
                readonly property bool changed: !!(rootRow.info && rootRow.info.Changed)
                title: root._rootTitle(rootRow.modelData)
                description: rootRow.info
                    ? (rootRow.info.Entries + (rootRow.info.Entries === 1 ? " entry" : " entries")
                        + (rootRow.changed ? " — changed since the last accept." : " — matches the accepted baseline."))
                    : "Not present on this host."

                Row {
                    spacing: root.gap
                    Widgets.StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !!rootRow.info
                        kind: "label"; sizeStep: 0
                        tone: rootRow.changed ? "warn" : "success"
                        text: rootRow.changed ? "changed" : "clean"
                    }
                    Widgets.SmallButton {
                        anchors.verticalCenter: parent.verticalCenter
                        label: root.acceptingRoot === rootRow.modelData ? "Accepting…" : "Accept"
                        enabled: root.acceptingRoot.length === 0 && !root.auditing
                        onClicked: root.acceptRoot(rootRow.modelData)
                    }
                }
            }
        }

        Modules.SettingsRow {
            title: "Re-run audit"
            description: "Runs `phi pkg audit --json` again."
            Widgets.SmallButton {
                label: root.auditing ? "Running…" : "Re-run audit"
                enabled: !root.auditing && root.acceptingRoot.length === 0
                onClicked: root.runAudit()
            }
        }

        Widgets.Reveal {
            shown: root.acceptError.length > 0
            Modules.SettingsRow {
                wide: true
                title: "Accept failed"
                Widgets.StyledText { width: parent.width; wrapMode: Text.WordWrap; tone: "error"; text: root.acceptError }
            }
        }

        Widgets.Reveal {
            shown: root._problems.length > 0
            Modules.SettingsRow {
                wide: true
                title: "Malformed external.txt lines"
                Column {
                    width: parent.width
                    spacing: root.gap / 2
                    Repeater {
                        model: root._problems
                        Widgets.StyledText {
                            required property var modelData
                            width: parent.width
                            wrapMode: Text.WordWrap
                            kind: "label"; sizeStep: 0; tone: "error"
                            text: modelData.File + ":" + modelData.Line + "  " + modelData.Detail
                        }
                    }
                }
            }
        }
    }

    // ================================================================
    // Packages
    // ================================================================
    Modules.SettingsGroup {
        title: "Packages"
        optionId: "packages.managers"
        caption: "One list per manager. See available updates with `phi pkg check` in a terminal; apply them with `phi update` — both need a TTY for prompts, so they stay there."

        ManagerBlock {
            title: "phi-packages (" + root._entriesFor("phi-packages").length + ")"
            entries: root._entriesFor("phi-packages")
        }
        ManagerBlock {
            title: "pacman — core/extra (" + root._entriesFor("T0 (core/extra)").length + ")"
            entries: root._entriesFor("T0 (core/extra)")
        }
        ManagerBlock {
            title: "AUR (" + root._entriesFor("AUR").length + ")"
            entries: root._entriesFor("AUR")
            placeholder: "Empty — AUR packages are not allowed. A non-empty list here is a policy violation."
        }
        ManagerBlock {
            title: "npm (global)"
            placeholder: "Not implemented yet — list with `npm ls -g --depth 0`."
        }
        ManagerBlock {
            title: "flatpak"
            placeholder: "Not implemented yet — list with `flatpak list --app`."
        }
        ManagerBlock {
            title: "AppImage — ~/Applications (" + root.appimages.length + ")"
            entries: root.appimages
            placeholder: "No .AppImage files in ~/Applications."
        }
        ManagerBlock {
            title: "external — TC/T2/T3/T4 (" + root.externalEntries.length + ")"
            entries: root.externalEntries
            tierStatus: true
            placeholder: "None declared."
        }
    }

    // ================================================================
    // Findings
    // ================================================================
    Modules.SettingsGroup {
        title: "Findings"
        optionId: "packages.findings"
        caption: root._findingsCount > 0
            ? "Grouped by check: drift (declared vs. installed), leak (escaped containment) and integrity (checksum)."
            : "Nothing to review."

        Widgets.StyledText {
            width: parent ? parent.width : 0
            visible: root._findingsCount === 0
            kind: "label"; sizeStep: 0
            text: "No findings."
        }

        FindingGroup {
            visible: root._findingsCount > 0
            title: "Drift (" + root._findingsFor("drift").length + ")"
            findings: root._findingsFor("drift")
        }
        FindingGroup {
            visible: root._findingsCount > 0
            title: "Leak (" + root._findingsFor("leak").length + ")"
            findings: root._findingsFor("leak")
        }
        FindingGroup {
            visible: root._findingsCount > 0
            title: "Integrity (" + root._findingsFor("integrity").length + ")"
            findings: root._findingsFor("integrity")
        }
    }
}

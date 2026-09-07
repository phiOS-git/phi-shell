import QtQml
import Quickshell
import qs.Config as Config

// phiOS — phi-shell entry point (master plan §8.2).
//
// `import qs.Config` is Quickshell's own config-relative module import
// (0.2+), not a generic relative-path import: `qs` always resolves to the
// folder shell.qml is in, and Quickshell's own docs recommend it over
// `import "./Config"` as more LSP-friendly. It is also the only mechanism
// confirmed to resolve a `pragma Singleton` file across directories — a
// plain relative import was not.
//
// S-20 is the structural skeleton only: nothing here is visible. The first
// real surface is the bar (S-22). What this file establishes now is the
// per-screen shape every later surface plugs into (ADR 077, "designed for N
// monitors from day one") — a Variants delegate instantiated once per
// Quickshell.screens entry, holding nothing yet, so a later step adds a
// PanelWindow to an existing per-screen slot instead of retrofitting one
// onto a hardcoded single instance.
//
// The onCompleted log line exists to give this step something concrete to
// verify. It touches Config.Appearance, which touches Config.Tokens, which
// only exists once `phi theme set` has rendered it (see Config/Tokens.example.qml
// and this repository's README) — so a clean log line here is proof the
// whole Config/ chain resolved. It also reads Config.Capabilities.gpuVendor:
// QML singletons instantiate lazily on first use, so without this the
// Capabilities singleton — and the Process/StdioCollector probe inside it —
// would never actually run during this step's own verification.

ShellRoot {
    id: root

    Variants {
        model: Quickshell.screens

        QtObject {
            required property ShellScreen modelData
            readonly property string screenName: modelData.name
        }
    }

    Component.onCompleted: {
        console.log("phi-shell: " + Quickshell.screens.length
            + " screen(s), variant=" + Config.Appearance.variant
            + ", gpu=" + Config.Capabilities.gpuVendor)
    }
}

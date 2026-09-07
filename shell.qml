import QtQml
import Quickshell
import "./Config" as Config

// phiOS — phi-shell entry point (master plan §8.2).
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
// verify: it touches Config.Appearance, which touches Config.Tokens, which
// only exists once `phi theme set` has rendered it (see Config/Tokens.example.qml
// and this repository's README) — so a clean log line here is also proof the
// whole Config/ chain resolved.

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
            + " screen(s), variant=" + Config.Appearance.variant)
    }
}

import QtQml
import Quickshell
import qs.Config as Config
import qs.Bar as Bar

// phiOS — phi-shell entry point (master plan §8.2).
//
// `import qs.Config`/`qs.Bar` are Quickshell's own config-relative module
// imports (0.2+), not generic relative-path ones: `qs` always resolves to
// the folder shell.qml is in, and Quickshell's own docs recommend it over
// `import "./Config"` as more LSP-friendly. It is also the only mechanism
// confirmed to resolve a `pragma Singleton` file across directories — a
// plain relative import was not.
//
// S-20's placeholder `QtObject` delegate (holding nothing, "the first real
// surface is the bar") is now `Bar.Bar` (S-22): one real PanelWindow per
// screen, instantiated through the exact per-screen slot S-20 built for
// this (ADR 077, "designed for N monitors from day one") rather than a
// hardcoded single instance retrofitted onto it.
//
// The onCompleted log line still exists for the same reason S-20 added
// it: touching Config.Appearance/Config.Capabilities.gpuVendor forces both
// singletons to actually instantiate (QML singletons are lazy on first
// use), so a clean log line is proof the whole Config/ chain resolved
// before Bar.Bar starts reading it.

ShellRoot {
    id: root

    Variants {
        model: Quickshell.screens

        Bar.Bar {
            required property ShellScreen modelData
            screen: modelData
        }
    }

    Component.onCompleted: {
        console.log("phi-shell: " + Quickshell.screens.length
            + " screen(s), variant=" + Config.Appearance.variant
            + ", gpu=" + Config.Capabilities.gpuVendor)
    }
}

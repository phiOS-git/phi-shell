pragma Singleton
import Quickshell

// phiOS — design tokens, rendered by `phi theme set` (S-12) from
// design/tokens.common.sh + design/tokens.<variant>.sh via
// design/adapters.txt (S-20). GENERATED. Never edit by hand — edit the
// token files in phios-dotfiles and re-run `phi theme set`; the next render
// overwrites whatever is here.
//
// THIS FILE IS AN EXAMPLE, checked in so the shape is visible without
// running `phi theme set` first. It is a hand-rendered snapshot of the dark
// variant as design/tokens.dark.sh reads today (S-20) and is not
// regenerated automatically — it will drift from the real token files the
// moment either changes. The real Config/Tokens.qml is gitignored; this
// file is not it and nothing reads it at runtime.
//
// Every value is a string, units included ("14px", "120ms", "1ch"), exactly
// as design/tokens.common.sh's own contract requires: a consumer that needs
// a bare number strips the unit itself. Config/Appearance.qml is the only
// file allowed to read these — everything else reads Appearance.

Singleton {
    id: root

    readonly property string variant: "dark"

    // --- Tier 0: structure ---------------------------------------------
    readonly property string bg0: "#1a1918"
    readonly property string bg1: "#242320"
    readonly property string bg2: "#2e2d2a"
    readonly property string bg3: "#393835"
    readonly property string fg0: "#d6d1c9"
    readonly property string fg1: "#a8a39b"
    readonly property string fg2: "#7d786f"
    readonly property string fg3: "#544f47"
    readonly property string border: "#242320"
    readonly property string borderStrong: "#3e3d3a"
    readonly property string overlayScrim: "#00000099"

    // --- Tier 1: accent --------------------------------------------------
    readonly property string accent: "#d3a0ac"
    readonly property string accentFg: "#1a1918"

    // --- Tier 2: semantic --------------------------------------------------
    readonly property string error: "#b57b73"
    readonly property string errorFg: "#1a1918"
    readonly property string warn: "#c0a874"
    readonly property string warnFg: "#1a1918"
    readonly property string success: "#8fa77e"
    readonly property string successFg: "#1a1918"
    readonly property string info: "#7f95ab"
    readonly property string infoFg: "#1a1918"

    // --- Tier 3: syntax --------------------------------------------------
    readonly property string syntax1: "#d3a0ac"
    readonly property string syntax2: "#8fa77e"
    readonly property string syntax3: "#c0a874"
    readonly property string syntax4: "#7f95ab"
    readonly property string syntax5: "#b57b73"
    readonly property string syntax6: "#7d786f"

    // --- Selection, terminal cursor ---------------------------------------
    readonly property string selectionBg: "#242320"
    readonly property string selectionFg: "#d6d1c9"
    readonly property string cursorTerm: "#d3a0ac"

    // --- ANSI 16 -----------------------------------------------------------
    readonly property string ansi0: "#242320"
    readonly property string ansi1: "#b57b73"
    readonly property string ansi2: "#8fa77e"
    readonly property string ansi3: "#c0a874"
    readonly property string ansi4: "#7f95ab"
    readonly property string ansi5: "#d3a0ac"
    readonly property string ansi6: "#7f95ab"
    readonly property string ansi7: "#d6d1c9"
    readonly property string ansi8: "#7d786f"
    readonly property string ansi9: "#b57b73"
    readonly property string ansi10: "#8fa77e"
    readonly property string ansi11: "#c0a874"
    readonly property string ansi12: "#7f95ab"
    readonly property string ansi13: "#d3a0ac"
    readonly property string ansi14: "#7f95ab"
    readonly property string ansi15: "#d6d1c9"

    // --- Typography --------------------------------------------------------
    readonly property string fontMono: "Iosevka"
    readonly property string fontReading: "Source Serif 4"
    readonly property string fontUi: "Source Sans 3"
    readonly property string fontSymbol: "Symbols Nerd Font"

    // --- Size scale --------------------------------------------------------
    readonly property string fontSize0: "12px"
    readonly property string fontSize1: "14px"
    readonly property string fontSize2: "16px"
    readonly property string fontSize3: "18px"
    readonly property string fontSize4: "20px"
    readonly property string fontSize5: "22px"
    readonly property string fontSize6: "25px"

    // --- Spacing -------------------------------------------------------
    readonly property string space1: "1ch"
    readonly property string space2: "2ch"
    readonly property string space3: "3ch"
    readonly property string space4: "4ch"
    readonly property string space5: "6ch"
    readonly property string space6: "8ch"

    // --- Shape -------------------------------------------------------
    readonly property string radiusBase: "2px"
    readonly property string radiusPill: "9999px"

    // --- Layering -------------------------------------------------------
    readonly property string zBase: "0"
    readonly property string zBar: "100"
    readonly property string zPopover: "200"
    readonly property string zModal: "300"
    readonly property string zTooltip: "400"
    readonly property string zNotification: "500"

    // --- Motion -------------------------------------------------------
    readonly property string motionAPeriod: "1600ms"
    readonly property string motionAEasing: "linear"
    readonly property string motionBDuration: "120ms"
    readonly property string motionBEasing: "ease-out"
    readonly property string motionCTypeStep: "24ms"
    readonly property string motionCScramble: "600ms"
    readonly property string motionCEasing: "linear"
    readonly property string motionDDuration: "0ms"
}

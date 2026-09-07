pragma Singleton
import QtQuick
import Quickshell

// phiOS — semantic roles over the raw design tokens (master plan §6.2, §6.7,
// §8.2). Config/Tokens.qml stores everything as a string with its unit
// attached, exactly as design/tokens.common.sh's own contract requires; this
// file is the one place that turns a token's stored string ("120ms", "14px",
// "#1a1918") into the QML type a consumer actually wants (color, real, int),
// and the one place a future role rename or unit change has to happen.
//
// S-20 AGENT contract: every other file in this shell reads Appearance,
// never Config/Tokens.qml directly.
//
// Only tiers an actual shell surface can plausibly use are exposed. Tier 3
// (syntax highlighting) and the ANSI 16 / selection / terminal-cursor tokens
// are terminal-emulator concepts — no surface in master plan §8.3 needs them
// — so they stay on Tokens, unexposed here, until a real consumer asks.

Singleton {
    id: root

    readonly property string variant: Tokens.variant

    // --- Structure ---------------------------------------------------------
    readonly property color background: _color(Tokens.bg0)
    readonly property color surface1: _color(Tokens.bg1)
    readonly property color surface2: _color(Tokens.bg2)
    readonly property color surface3: _color(Tokens.bg3)
    readonly property color textPrimary: _color(Tokens.fg0)
    readonly property color textSecondary: _color(Tokens.fg1)
    readonly property color textMuted: _color(Tokens.fg2)
    readonly property color textFaint: _color(Tokens.fg3)
    readonly property color border: _color(Tokens.border)
    readonly property color borderStrong: _color(Tokens.borderStrong)
    readonly property color overlayScrim: _color(Tokens.overlayScrim)

    // --- Accent and semantic state ------------------------------------------
    readonly property color accent: _color(Tokens.accent)
    readonly property color accentText: _color(Tokens.accentFg)
    readonly property color error: _color(Tokens.error)
    readonly property color errorText: _color(Tokens.errorFg)
    readonly property color warn: _color(Tokens.warn)
    readonly property color warnText: _color(Tokens.warnFg)
    readonly property color success: _color(Tokens.success)
    readonly property color successText: _color(Tokens.successFg)
    readonly property color info: _color(Tokens.info)
    readonly property color infoText: _color(Tokens.infoFg)

    // --- Typography ----------------------------------------------------
    readonly property string fontMono: Tokens.fontMono
    readonly property string fontReading: Tokens.fontReading
    readonly property string fontUi: Tokens.fontUi
    readonly property string fontSymbol: Tokens.fontSymbol

    readonly property real fontSize0: _px(Tokens.fontSize0)
    readonly property real fontSize1: _px(Tokens.fontSize1)
    readonly property real fontSize2: _px(Tokens.fontSize2)
    readonly property real fontSize3: _px(Tokens.fontSize3)
    readonly property real fontSize4: _px(Tokens.fontSize4)
    readonly property real fontSize5: _px(Tokens.fontSize5)
    readonly property real fontSize6: _px(Tokens.fontSize6)

    // Spacing stays in units of 1ch of fontMono, not px: design/README.md
    // is explicit that storing px here would silently break the moment
    // Q-N01 changes the mono family. A caller that needs px measures the
    // font itself and multiplies.
    readonly property real space1: _ch(Tokens.space1)
    readonly property real space2: _ch(Tokens.space2)
    readonly property real space3: _ch(Tokens.space3)
    readonly property real space4: _ch(Tokens.space4)
    readonly property real space5: _ch(Tokens.space5)
    readonly property real space6: _ch(Tokens.space6)

    // --- Shape ------------------------------------------------------
    readonly property real radiusBase: _px(Tokens.radiusBase)
    readonly property real radiusPill: _px(Tokens.radiusPill)

    // --- Layering ------------------------------------------------------
    readonly property int zBase: parseInt(Tokens.zBase)
    readonly property int zBar: parseInt(Tokens.zBar)
    readonly property int zPopover: parseInt(Tokens.zPopover)
    readonly property int zModal: parseInt(Tokens.zModal)
    readonly property int zTooltip: parseInt(Tokens.zTooltip)
    readonly property int zNotification: parseInt(Tokens.zNotification)

    // --- Motion (master plan §6.5) ------------------------------------------
    // Easing stays a string: mapping "linear"/"ease-out" onto a QML
    // Easing.Type enum needs the animation type it applies to in scope,
    // which belongs to the widget that animates (S-21) or the motion step
    // itself (S-52), not to this singleton.
    readonly property int motionAPeriod: _ms(Tokens.motionAPeriod)
    readonly property string motionAEasing: Tokens.motionAEasing
    readonly property int motionBDuration: _ms(Tokens.motionBDuration)
    readonly property string motionBEasing: Tokens.motionBEasing
    readonly property int motionCTypeStep: _ms(Tokens.motionCTypeStep)
    readonly property int motionCScramble: _ms(Tokens.motionCScramble)
    readonly property string motionCEasing: Tokens.motionCEasing
    readonly property int motionDDuration: _ms(Tokens.motionDDuration)

    function _px(value) { return parseFloat(value) }
    function _ms(value) { return parseInt(value) }
    function _ch(value) { return parseFloat(value) }

    // Tokens store an 8-digit colour as #rrggbbaa (CSS order, see
    // design/tokens.dark.sh's own note on PHI_OVERLAY_SCRIM), not Qt's
    // #aarrggbb — parsed by hand so a scrim's alpha byte never lands in the
    // wrong place. 6-digit values pass through with alpha 1.
    function _color(hex) {
        const h = hex.replace("#", "")
        const r = parseInt(h.substring(0, 2), 16) / 255
        const g = parseInt(h.substring(2, 4), 16) / 255
        const b = parseInt(h.substring(4, 6), 16) / 255
        const a = h.length >= 8 ? parseInt(h.substring(6, 8), 16) / 255 : 1
        return Qt.rgba(r, g, b, a)
    }
}

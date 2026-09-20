pragma Singleton
import QtQuick
import Quickshell


Singleton {
    id: root

    // Colors.qml not Tokens.qml: variant switch rewrites Colors.json, never
    // Appearance source, so reading doesn't force full re-evaluation.
    readonly property string variant: Colors.variant

    // --- Structure ---------------------------------------------------------
    readonly property color background: _color(_tok("bg-0", Colors.bg0))
    readonly property color surface1: _color(_tok("bg-1", Colors.bg1))
    readonly property color surface2: _color(_tok("bg-2", Colors.bg2))
    readonly property color surface3: _color(_tok("bg-3", Colors.bg3))
    readonly property color textPrimary: _color(_tok("fg-0", Colors.fg0))
    readonly property color textSecondary: _color(_tok("fg-1", Colors.fg1))
    readonly property color textMuted: _color(_tok("fg-2", Colors.fg2))
    readonly property color textFaint: _color(_tok("fg-3", Colors.fg3))
    readonly property color border: _color(_tok("border", Colors.border))
    readonly property color borderStrong: _color(_tok("border-strong", Colors.borderStrong))
    readonly property color overlayScrim: _color(Colors.overlayScrim)
    // For blocking surfaces only — not overridable, like overlayScrim.
    readonly property color overlayScrimStrong: _color(Colors.overlayScrimStrong)

    // --- Accent and semantic state ------------------------------------------
    readonly property color accent: _color(_tok("accent", Colors.accent))
    readonly property color accentText: {
        var explicit = _tok("accent-fg", null)
        if (explicit !== null) return _color(explicit)
        // Auto-flip when accent overridden but text color not: light accent
        // needs dark text.
        if (ThemeOverrides.value("accent") !== null) return _bestText(root.accent)
        return _color(Colors.accentFg)
    }
    readonly property color error: _color(_tok("error", Colors.error))
    readonly property color errorText: _color(Colors.errorFg)
    readonly property color warn: _color(_tok("warn", Colors.warn))
    readonly property color warnText: _color(Colors.warnFg)
    readonly property color success: _color(_tok("success", Colors.success))
    readonly property color successText: _color(Colors.successFg)
    readonly property color info: _color(_tok("info", Colors.info))
    readonly property color infoText: _color(Colors.infoFg)

    // --- phiOS style grammar -------------------------------------------
    // main (bg-0) and opposite (fg-0) carry the shell. accent for fine detail
    // only: titles, focus ring, agent state. Selection: full inversion.
    readonly property color colorMain: root.background
    readonly property color colorOpposite: root.textPrimary

    // Panels: main background, opposite border (borderWidthStrong), opposite text.
    readonly property color panelBackground: root.colorMain
    readonly property color panelBorder: root.colorOpposite
    readonly property color panelText: root.colorOpposite

    // Bar has no fill. Button is opposite-coloured glyph on wallpaper; selected
    // state paints full block.
    readonly property color barText: root.colorOpposite

    // Selection: opposite block, text flips to main.
    readonly property color selectionBackground: root.colorOpposite
    readonly property color selectionText: root.colorMain

    // The one control state that still shows accent — a ring, not a fill.
    readonly property color focusRing: root.accent

    // Subtle hover wash toward contrast. Mix ratio, not design token.
    readonly property color panelHover: _mix(root.colorMain, root.colorOpposite, 0.08)
    // Bar button: translucent main fill + hairline border, wallpaper shows
    // through. Hover reuses panelHover; selected is opposite/main inversion.
    readonly property color barButtonBackground: Qt.rgba(root.colorMain.r,
        root.colorMain.g, root.colorMain.b, 0.72)
    readonly property color barButtonBorder: Qt.rgba(root.colorOpposite.r,
        root.colorOpposite.g, root.colorOpposite.b, 0.22)

    // --- Typography ----------------------------------------------------
    readonly property string fontMono: _tok("font-mono", Tokens.fontMono)
    readonly property string fontReading: _tok("font-reading", Tokens.fontReading)
    readonly property string fontUi: _tok("font-ui", Tokens.fontUi)
    readonly property string fontSymbol: Tokens.fontSymbol

    // One multiplier over the whole generated size scale (settings panel exposes
    // this instead of seven individual sizes).
    readonly property real fontScale: _scale("font-scale", Tokens.fontScale)

    readonly property real fontSize0: _px(Tokens.fontSize0) * root.fontScale
    readonly property real fontSize1: _px(Tokens.fontSize1) * root.fontScale
    readonly property real fontSize2: _px(Tokens.fontSize2) * root.fontScale
    readonly property real fontSize3: _px(Tokens.fontSize3) * root.fontScale
    readonly property real fontSize4: _px(Tokens.fontSize4) * root.fontScale
    readonly property real fontSize5: _px(Tokens.fontSize5) * root.fontScale
    readonly property real fontSize6: _px(Tokens.fontSize6) * root.fontScale

    // Spacing in units of fontMono 1ch, not px — stores px would break if font
    // changes. Callers needing px measure the font and multiply.
    readonly property real spaceScale: _scale("space-scale", Tokens.spaceScale)
    readonly property real space1: _ch(Tokens.space1) * root.spaceScale
    readonly property real space2: _ch(Tokens.space2) * root.spaceScale
    readonly property real space3: _ch(Tokens.space3) * root.spaceScale
    readonly property real space4: _ch(Tokens.space4) * root.spaceScale
    readonly property real space5: _ch(Tokens.space5) * root.spaceScale
    readonly property real space6: _ch(Tokens.space6) * root.spaceScale

    // --- Shape ------------------------------------------------------
    readonly property real radiusBase: _px(_tok("radius-base", Tokens.radiusBase))
    readonly property real radiusPill: _px(Tokens.radiusPill)
    readonly property real radiusSmall: _pxOr(_tok("radius-small", Tokens.radiusSmall), root.radiusBase)
    readonly property real radiusLarge: _pxOr(_tok("radius-large", Tokens.radiusLarge), root.radiusBase)
    readonly property real borderWidth: _px(Tokens.borderWidth)
    readonly property real borderWidthStrong: _pxOr(Tokens.borderWidthStrong, root.borderWidth)
    readonly property real panelPadding: _pxOr(Tokens.panelPadding, root.radiusBase)

    // Inset bar-surfaces keep from edges and corner radius. Both user-editable
    // (Theme › Shape & spacing). Fallbacks cover hot-reload before `phi theme set`.
    readonly property real panelGap: _pxOr(_tok("panel-gap", Tokens.panelGap), 4)
    readonly property real panelRadius: _pxOr(_tok("panel-radius", Tokens.panelRadius), 6)
    // Widgets/Meter visible track height — thin rail, not settings-exposed.
    readonly property real sliderThickness: _pxOr(Tokens.sliderThickness, 4)

    // --- Layering ------------------------------------------------------
    readonly property int zBase: parseInt(Tokens.zBase)
    readonly property int zBar: parseInt(Tokens.zBar)
    readonly property int zPopover: parseInt(Tokens.zPopover)
    readonly property int zModal: parseInt(Tokens.zModal)
    readonly property int zTooltip: parseInt(Tokens.zTooltip)
    readonly property int zNotification: parseInt(Tokens.zNotification)

    // --- Motion ------------------------------------------------------
    // Easing stays string for A/C/D: mapping to Easing.Type needs animation type
    // in scope (the widget). Category B exception: resolved once, per-user editable.
    readonly property int motionAPeriod: _ms(_tok("motion-a-period", Tokens.motionAPeriod))
    readonly property string motionAEasing: Tokens.motionAEasing
    readonly property int motionBDuration: _ms(_tok("motion-b-duration", Tokens.motionBDuration))
    readonly property string motionBEasing: Tokens.motionBEasing
    // Kept for stragglers; new code uses motionBCurve (OutQuad equivalent).
    readonly property int motionBEasingType: motionBEasing === "linear" ? Easing.Linear : Easing.OutQuad
    // Category-B curve: easing.bezierCurve list, four editable control points
    // plus final (1,1). Default reproduces OutQuad.
    readonly property var motionBCurve: {
        var raw = _tok("motion-b-bezier", Tokens.motionBBezier)
        var p = String(raw || "").split(",").map(function (s) { return parseFloat(s) })
        if (p.length < 4 || p.some(function (n) { return isNaN(n) })) p = [0.25, 0.46, 0.45, 0.94]
        return [p[0], p[1], p[2], p[3], 1, 1]
    }
    readonly property int motionCTypeStep: _ms(_tok("motion-c-type-step", Tokens.motionCTypeStep))
    readonly property int motionCScramble: _ms(_tok("motion-c-scramble", Tokens.motionCScramble))
    readonly property string motionCEasing: Tokens.motionCEasing
    readonly property int motionDDuration: _ms(_tok("motion-d-duration", Tokens.motionDDuration))

    // --- Wallpaper textures -------------------------------------------- Catalogue
    // is a design decision; falls back before `phi theme set` regenerates.
    readonly property var textureModes: {
        var s = String(Tokens.textureModes || "").trim()
        return s.length > 0 ? s.split(/\s+/) : ["grain", "noise", "paper", "leather", "rock", "fabric"]
    }
    readonly property int textureIntensityDefault: {
        var n = parseInt(Tokens.textureIntensityDefault)
        return isNaN(n) ? 40 : n
    }

    // --- helpers ------------------------------------------------------ parseFloat with fallback.
    // Token string always carries unit ("14px"); parseFloat stops there. _pxOr
    // fallback covers window after token added but before `phi theme set` regenerates.
    function _pxOr(value, fallback) {
        var n = parseFloat(value)
        return isNaN(n) ? fallback : n
    }
    function _px(value) { return root._pxOr(value, 0) }
    function _ch(value) { return root._pxOr(value, 0) }
    function _ms(value) {
        var n = parseInt(value)
        return isNaN(n) ? 0 : n
    }

    // Scale multiplier: identity by default, dimensionless.
    function _scale(key, tokenValue) {
        var raw = root._tok(key, (tokenValue === undefined || tokenValue === null || String(tokenValue).length === 0) ? "1" : tokenValue)
        var n = parseFloat(raw)
        return (isNaN(n) || n <= 0) ? 1 : n
    }

    // Merge Config/ThemeOverrides value over generated token. `null` fallback
    // asks "is this overridden at all" (see accentText).
    function _tok(key, fallback) {
        var o = ThemeOverrides.value(key)
        return (o === null || o === undefined || String(o).length === 0) ? fallback : o
    }

    function _mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
    }

    // Config/Tokens.qml and Colors.qml private to this file — settings panel gets
    // defaults through tokenDefault() instead of reading directly.
    function tokenDefault(key) {
        switch (key) {
        case "accent": return Colors.accent
        case "accent-fg": return Colors.accentFg
        case "bg-0": return Colors.bg0
        case "bg-1": return Colors.bg1
        case "bg-2": return Colors.bg2
        case "bg-3": return Colors.bg3
        case "fg-0": return Colors.fg0
        case "fg-1": return Colors.fg1
        case "fg-2": return Colors.fg2
        case "fg-3": return Colors.fg3
        case "border": return Colors.border
        case "border-strong": return Colors.borderStrong
        case "error": return Colors.error
        case "warn": return Colors.warn
        case "success": return Colors.success
        case "info": return Colors.info
        case "font-mono": return Tokens.fontMono
        case "font-reading": return Tokens.fontReading
        case "font-ui": return Tokens.fontUi
        case "font-scale": return root._scaleString(Tokens.fontScale)
        case "space-scale": return root._scaleString(Tokens.spaceScale)
        case "radius-base": return Tokens.radiusBase
        case "radius-small": return root._numString(Tokens.radiusSmall, Tokens.radiusBase)
        case "radius-large": return root._numString(Tokens.radiusLarge, Tokens.radiusBase)
        case "panel-gap": return root._numString(Tokens.panelGap, "4px")
        case "panel-radius": return root._numString(Tokens.panelRadius, "6px")
        }
        return ""
    }
    function _scaleString(v) {
        return (v === undefined || v === null || String(v).length === 0) ? "1" : String(v)
    }
    function _numString(v, fallback) {
        return (v === undefined || v === null || String(v).length === 0) ? String(fallback) : String(v)
    }

    // Effective (override-aware) string for a token key — what settings shows
    // and what reset restores to.
    function tokenValue(key) {
        return String(root._tok(key, root.tokenDefault(key)) || "")
    }

    // Pick main or opposite as readable text over arbitrary accent — relative
    // luminance, WCAG-style.
    function _bestText(c) {
        var lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
        return lum > 0.5 ? root.colorMain : root.colorOpposite
    }

    // Tokens store 8-digit colour as #rrggbbaa (CSS not Qt), hand-parsed so
    // alpha never lands wrong. 6-digit: alpha 1. Malformed: transparent.
    function _color(hex) {
        if (hex === undefined || hex === null) return Qt.rgba(0, 0, 0, 0)
        var h = String(hex).replace("#", "")
        if (h.length < 6) return Qt.rgba(0, 0, 0, 0)
        var r = parseInt(h.substring(0, 2), 16) / 255
        var g = parseInt(h.substring(2, 4), 16) / 255
        var b = parseInt(h.substring(4, 6), 16) / 255
        var a = h.length >= 8 ? parseInt(h.substring(6, 8), 16) / 255 : 1
        if (isNaN(r) || isNaN(g) || isNaN(b) || isNaN(a)) return Qt.rgba(0, 0, 0, 0)
        return Qt.rgba(r, g, b, a)
    }
}

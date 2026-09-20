pragma Singleton
import QtQuick
import Quickshell


Singleton {
    id: root

    // Colors.qml, not Tokens.qml: a variant switch rewrites Colors.json, never
    // this singleton's own source, so reading it doesn't force a destructive
    // full re-evaluation of Appearance itself.
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
    // For full-attention blocking surfaces only — not overridable, same as
    // overlayScrim.
    readonly property color overlayScrimStrong: _color(Colors.overlayScrimStrong)

    // --- Accent and semantic state ------------------------------------------
    readonly property color accent: _color(_tok("accent", Colors.accent))
    readonly property color accentText: {
        var explicit = _tok("accent-fg", null)
        if (explicit !== null) return _color(explicit)
        // Auto-flip when accent is overridden but its text colour is not: a
        // user-picked light accent needs dark text, and vice versa.
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
    // "main" (bg-0) and "opposite" (fg-0, its inverse) carry the whole shell.
    // accent is fine detail only — titles, the focus ring, the Φ agent
    // processing state — never a generic selected/active fill.
    // Selection is a full inversion between main and opposite.
    readonly property color colorMain: root.background
    readonly property color colorOpposite: root.textPrimary

    // Panels: main background, opposite border (borderWidthStrong), text in
    // the opposite colour.
    readonly property color panelBackground: root.colorMain
    readonly property color panelBorder: root.colorOpposite
    readonly property color panelText: root.colorOpposite

    // The bar has no fill of its own. A bar button is an opposite-coloured
    // glyph/label sitting on the wallpaper; only its selected state paints a
    // full block. See Widgets/WidgetStates.js surfaceColors().
    readonly property color barText: root.colorOpposite

    // Selection / active item: a block of the opposite colour, text flips to
    // main.
    readonly property color selectionBackground: root.colorOpposite
    readonly property color selectionText: root.colorMain

    // The one control state that still shows accent — a ring, not a fill.
    readonly property color focusRing: root.accent

    // Subtle hover wash, one step toward the contrast colour. A bare mix
    // ratio, not a design token — same latitude as WidgetStates.js's
    // INACTIVE_OPACITY.
    readonly property color panelHover: _mix(root.colorMain, root.colorOpposite, 0.08)
    // A bar button's resting surface: translucent main-coloured fill plus a
    // hairline border, so the wallpaper still shows through. Hover reuses
    // panelHover; selected state is the full opposite/main inversion.
    readonly property color barButtonBackground: Qt.rgba(root.colorMain.r,
        root.colorMain.g, root.colorMain.b, 0.72)
    readonly property color barButtonBorder: Qt.rgba(root.colorOpposite.r,
        root.colorOpposite.g, root.colorOpposite.b, 0.22)

    // --- Typography ----------------------------------------------------
    readonly property string fontMono: _tok("font-mono", Tokens.fontMono)
    readonly property string fontReading: _tok("font-reading", Tokens.fontReading)
    readonly property string fontUi: _tok("font-ui", Tokens.fontUi)
    readonly property string fontSymbol: Tokens.fontSymbol

    // One multiplier over the whole generated size scale — the settings panel
    // exposes this rather than seven individual sizes.
    readonly property real fontScale: _scale("font-scale", Tokens.fontScale)

    readonly property real fontSize0: _px(Tokens.fontSize0) * root.fontScale
    readonly property real fontSize1: _px(Tokens.fontSize1) * root.fontScale
    readonly property real fontSize2: _px(Tokens.fontSize2) * root.fontScale
    readonly property real fontSize3: _px(Tokens.fontSize3) * root.fontScale
    readonly property real fontSize4: _px(Tokens.fontSize4) * root.fontScale
    readonly property real fontSize5: _px(Tokens.fontSize5) * root.fontScale
    readonly property real fontSize6: _px(Tokens.fontSize6) * root.fontScale

    // Spacing stays in units of 1ch of fontMono, not px — storing px would
    // silently break if the mono family ever changes. A caller that needs px
    // measures the font itself and multiplies.
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

    // Inset that-the-bar surfaces keep from the bar and screen edges, and the
    // corner radius they round at. Both per-user editable (Theme › Shape &
    // spacing). Fallbacks cover the hot-reload window before `phi theme set`
    // regenerates Tokens.qml with these keys.
    readonly property real panelGap: _pxOr(_tok("panel-gap", Tokens.panelGap), 4)
    readonly property real panelRadius: _pxOr(_tok("panel-radius", Tokens.panelRadius), 6)
    // Widgets/Meter's visible track height — a thin rail. Not
    // settings-exposed.
    readonly property real sliderThickness: _pxOr(Tokens.sliderThickness, 4)

    // --- Layering ------------------------------------------------------
    readonly property int zBase: parseInt(Tokens.zBase)
    readonly property int zBar: parseInt(Tokens.zBar)
    readonly property int zPopover: parseInt(Tokens.zPopover)
    readonly property int zModal: parseInt(Tokens.zModal)
    readonly property int zTooltip: parseInt(Tokens.zTooltip)
    readonly property int zNotification: parseInt(Tokens.zNotification)

    // --- Motion ------------------------------------------------------
    // Easing stays a string for categories A/C/D: mapping "linear"/ "ease-out"
    // onto a QML Easing.Type enum needs the animation type in scope (belongs
    // to the animating widget), not this singleton.
    // Category B is the exception — every widget animates state transitions on it, so it's resolved once,.
    // Durations and the category-B curve are per-user editable, merged over
    // the generated token the same way the palette is.
    readonly property int motionAPeriod: _ms(_tok("motion-a-period", Tokens.motionAPeriod))
    readonly property string motionAEasing: Tokens.motionAEasing
    readonly property int motionBDuration: _ms(_tok("motion-b-duration", Tokens.motionBDuration))
    readonly property string motionBEasing: Tokens.motionBEasing
    // Kept for any straggler; new code uses motionBCurve. OutQuad is the enum
    // equivalent of the default bezier.
    readonly property int motionBEasingType: motionBEasing === "linear" ? Easing.Linear : Easing.OutQuad
    // Category-B curve as an easing.bezierCurve list: four editable control
    // points plus the mandatory final (1,1). Default reproduces
    // Easing.OutQuad.
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

    // --- Wallpaper textures -------------------------------------------- Catalogue is a design decision;
    // falls back to the known set for the hot-reload window before `phi theme
    // set` regenerates Tokens.qml with this key.
    readonly property var textureModes: {
        var s = String(Tokens.textureModes || "").trim()
        return s.length > 0 ? s.split(/\s+/) : ["grain", "noise", "paper", "leather", "rock", "fabric"]
    }
    readonly property int textureIntensityDefault: {
        var n = parseInt(Tokens.textureIntensityDefault)
        return isNaN(n) ? 40 : n
    }

    // --- helpers ------------------------------------------------------ parseFloat with a fallback.
    // A token string always carries its unit ("14px") and parseFloat stops there.
    // `_pxOr`'s fallback covers the transient window after a token is added to
    // design/tokens.*.sh but before `phi theme set` has regenerated
    // Config/Tokens.qml — the read is `undefined`, and falling back to a value
    // that DOES resolve is safer for one hot-reload than NaN propagating
    // through layout math.
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

    // A scale multiplier: identity by default, dimensionless.
    function _scale(key, tokenValue) {
        var raw = root._tok(key, (tokenValue === undefined || tokenValue === null || String(tokenValue).length === 0) ? "1" : tokenValue)
        var n = parseFloat(raw)
        return (isNaN(n) || n <= 0) ? 1 : n
    }

    // Merge a Config/ThemeOverrides.qml value over a generated token. Passing
    // `null` as the fallback is how a getter asks "is this overridden at all"
    // (see accentText).
    function _tok(key, fallback) {
        var o = ThemeOverrides.value(key)
        return (o === null || o === undefined || String(o).length === 0) ? fallback : o
    }

    function _mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
    }

    // Config/Tokens.qml and Config/Colors.qml are private to this file — the
    // settings panel gets a key's generated default through instead of reading
    // them directly.
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

    // The effective (override-aware) string for a token key — what the
    // settings field shows, and what a reset restores to (tokenDefault).
    function tokenValue(key) {
        return String(root._tok(key, root.tokenDefault(key)) || "")
    }

    // Pick main or opposite as the readable text colour over an arbitrary
    // (user-picked) accent — relative luminance, WCAG-style coefficients.
    function _bestText(c) {
        var lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
        return lum > 0.5 ? root.colorMain : root.colorOpposite
    }

    // Tokens store an 8-digit colour as #rrggbbaa (CSS order), not Qt's
    // #aarrggbb — parsed by hand — scrim's alpha byte never lands in the wrong
    // place. 6-digit values pass through with alpha 1; a malformed or
    // undefined value yields transparent.
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

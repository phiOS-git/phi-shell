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
// OOP-02 (shell restyle) layered two things on here without touching that
// contract:
//
//   1. Config/ThemeOverrides.qml is merged over Tokens at read time, via
//      _tok(). The settings panel's Theme section (OOP-07) writes per-user
//      overrides for the tokens it exposes as editable — accent, the
//      structural + semantic palette, the font families, the font/spacing
//      scale and the radii. An unset override falls straight through to the
//      generated token, so nothing changes until the user sets something.
//
//   2. A named style-grammar layer (colorMain / colorOpposite / panel* /
//      barIsle* / selection* / focusRing) so the restyle's rule — two
//      structural colours carry the whole shell, accent is fine detail
//      only, selection is a full inversion between the two — lives in
//      exactly one file, and the settings display can enumerate it.
//
// Only tiers an actual shell surface can plausibly use are exposed. Tier 3
// (syntax highlighting) and the ANSI 16 / selection / terminal-cursor tokens
// are terminal-emulator concepts — no surface in master plan §8.3 needs them
// — so they stay on Tokens, unexposed here, until a real consumer asks.

Singleton {
    id: root

    readonly property string variant: Tokens.variant

    // --- Structure ---------------------------------------------------------
    readonly property color background: _color(_tok("bg-0", Tokens.bg0))
    readonly property color surface1: _color(_tok("bg-1", Tokens.bg1))
    readonly property color surface2: _color(_tok("bg-2", Tokens.bg2))
    readonly property color surface3: _color(_tok("bg-3", Tokens.bg3))
    readonly property color textPrimary: _color(_tok("fg-0", Tokens.fg0))
    readonly property color textSecondary: _color(_tok("fg-1", Tokens.fg1))
    readonly property color textMuted: _color(_tok("fg-2", Tokens.fg2))
    readonly property color textFaint: _color(_tok("fg-3", Tokens.fg3))
    readonly property color border: _color(_tok("border", Tokens.border))
    readonly property color borderStrong: _color(_tok("border-strong", Tokens.borderStrong))
    readonly property color overlayScrim: _color(Tokens.overlayScrim)

    // --- Accent and semantic state ------------------------------------------
    readonly property color accent: _color(_tok("accent", Tokens.accent))
    readonly property color accentText: {
        var explicit = _tok("accent-fg", null)
        if (explicit !== null) return _color(explicit)
        // Auto-flip when the accent is overridden but its text colour is
        // not: a user-picked light accent needs dark text, and vice versa.
        if (ThemeOverrides.value("accent") !== null) return _bestText(root.accent)
        return _color(Tokens.accentFg)
    }
    readonly property color error: _color(_tok("error", Tokens.error))
    readonly property color errorText: _color(Tokens.errorFg)
    readonly property color warn: _color(_tok("warn", Tokens.warn))
    readonly property color warnText: _color(Tokens.warnFg)
    readonly property color success: _color(_tok("success", Tokens.success))
    readonly property color successText: _color(Tokens.successFg)
    readonly property color info: _color(_tok("info", Tokens.info))
    readonly property color infoText: _color(Tokens.infoFg)

    // --- phiOS style grammar (OOP-02) -------------------------------------
    // "main"     = bg-0: a warm near-black on the dark variant, a warm
    //              near-white on the light one.
    // "opposite" = fg-0: its inverse.
    // These two carry the whole shell. accent is fine detail only — titles,
    // the keyboard focus ring, the Φ agent processing state — never a
    // generic selected/active fill. Selection is a full inversion between
    // main and opposite.
    readonly property color colorMain: root.background
    readonly property color colorOpposite: root.textPrimary

    // Panels: main background, opposite border (borderWidthStrong, 2px),
    // text in the opposite colour.
    readonly property color panelBackground: root.colorMain
    readonly property color panelBorder: root.colorOpposite
    readonly property color panelText: root.colorOpposite

    // Status bar (OOP-21): the bar has no fill of its own — not the
    // window (always transparent), and no longer the isles either (item
    // 10). A bar button is just an opposite-coloured glyph/label sitting
    // on the wallpaper; only its selected state paints a full block
    // (opposite bg, main text — the same inversion a selected panel row
    // uses). Item 6: the bar's colours were the inverse of a panel's;
    // they now match. See Widgets/WidgetStates.js surfaceColors(), ambient
    // "isle".
    // Text placed directly on the bar (the centre isle's active-window
    // title) — the opposite colour, readable on the wallpaper.
    readonly property color barText: root.colorOpposite

    // Selection / active item: a block of the opposite colour, text flips
    // to main.
    readonly property color selectionBackground: root.colorOpposite
    readonly property color selectionText: root.colorMain

    // The one control state that still shows accent — a ring, not a fill.
    readonly property color focusRing: root.accent

    // Subtle hover wash, one small step toward the contrast colour, per
    // ambient surface. Not a design token: a single ratio kept in one
    // place, the same latitude Widgets/WidgetStates.js takes for
    // INACTIVE_OPACITY (not a colour, size or duration — the I-05 ban does
    // not reach a bare mix ratio).
    readonly property color panelHover: _mix(root.colorMain, root.colorOpposite, 0.08)
    // OOP-21: a bar button rests on the wallpaper with no fill, so its
    // hover cannot be a solid mix — it is a faint translucent wash of the
    // text colour instead.
    readonly property color barButtonHover: Qt.rgba(root.colorOpposite.r,
        root.colorOpposite.g, root.colorOpposite.b, 0.14)

    // --- Typography ----------------------------------------------------
    readonly property string fontMono: _tok("font-mono", Tokens.fontMono)
    readonly property string fontReading: _tok("font-reading", Tokens.fontReading)
    readonly property string fontUi: _tok("font-ui", Tokens.fontUi)
    readonly property string fontSymbol: Tokens.fontSymbol

    // One multiplier over the whole generated size scale — the settings
    // panel exposes this rather than seven individual sizes.
    readonly property real fontScale: _scale("font-scale", Tokens.fontScale)

    readonly property real fontSize0: _px(Tokens.fontSize0) * root.fontScale
    readonly property real fontSize1: _px(Tokens.fontSize1) * root.fontScale
    readonly property real fontSize2: _px(Tokens.fontSize2) * root.fontScale
    readonly property real fontSize3: _px(Tokens.fontSize3) * root.fontScale
    readonly property real fontSize4: _px(Tokens.fontSize4) * root.fontScale
    readonly property real fontSize5: _px(Tokens.fontSize5) * root.fontScale
    readonly property real fontSize6: _px(Tokens.fontSize6) * root.fontScale

    // Spacing stays in units of 1ch of fontMono, not px: design/README.md
    // is explicit that storing px here would silently break the moment
    // Q-N01 changes the mono family. A caller that needs px measures the
    // font itself and multiplies. One multiplier, same rationale as
    // fontScale.
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

    // --- Layering ------------------------------------------------------
    readonly property int zBase: parseInt(Tokens.zBase)
    readonly property int zBar: parseInt(Tokens.zBar)
    readonly property int zPopover: parseInt(Tokens.zPopover)
    readonly property int zModal: parseInt(Tokens.zModal)
    readonly property int zTooltip: parseInt(Tokens.zTooltip)
    readonly property int zNotification: parseInt(Tokens.zNotification)

    // --- Motion (master plan §6.5) ------------------------------------------
    // Easing stays a string for categories A/C/D: mapping "linear"/"ease-out"
    // onto a QML Easing.Type enum needs the animation type it applies to in
    // scope, which belongs to the widget that animates, not to this
    // singleton. Category B is the exception, resolved here rather than in
    // every widget: S-21's whole widget library animates state transitions
    // on this one category, always as a ColorAnimation/NumberAnimation
    // Behavior, so there is exactly one place this string-to-curve mapping
    // happens instead of one copy per widget.
    // OOP: settings-overhaul batch E — the durations and the category-B
    // curve are per-user editable (the animation section of the Theme
    // panel), merged over the generated token the same way the palette is.
    // "All major transitions must have mapped variables to be edited": the
    // four style-plan categories ARE that mapping — every Behavior in this
    // shell routes its duration/curve through category B, so making B
    // editable reaches every panel, drawer, workspace and notification
    // transition at once.
    readonly property int motionAPeriod: _ms(_tok("motion-a-period", Tokens.motionAPeriod))
    readonly property string motionAEasing: Tokens.motionAEasing
    readonly property int motionBDuration: _ms(_tok("motion-b-duration", Tokens.motionBDuration))
    readonly property string motionBEasing: Tokens.motionBEasing
    // Kept for any straggler; new code uses motionBCurve. OutQuad is the
    // enum equivalent of the default bezier below.
    readonly property int motionBEasingType: motionBEasing === "linear" ? Easing.Linear : Easing.OutQuad
    // The category-B curve as an easing.bezierCurve list: four editable
    // control points plus the mandatory final (1,1). Default reproduces
    // Easing.OutQuad, so nothing changes until the user edits it.
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

    // --- Wallpaper textures (OOP: settings-overhaul) ----------------------
    // The catalogue is a design decision (design/tokens.common.sh
    // PHI_TEXTURE_MODES); the settings panel's wallpaper section reads it
    // from here rather than hardcoding the list or touching Tokens directly.
    // Falls back to the known set for the hot-reload window before `phi
    // theme set` has regenerated Tokens.qml with the new key.
    readonly property var textureModes: {
        var s = String(Tokens.textureModes || "").trim()
        return s.length > 0 ? s.split(/\s+/) : ["grain", "noise", "paper", "leather", "rock", "fabric"]
    }
    readonly property int textureIntensityDefault: {
        var n = parseInt(Tokens.textureIntensityDefault)
        return isNaN(n) ? 40 : n
    }

    // --- helpers ------------------------------------------------------
    // parseFloat with a fallback. A design-token string always carries its
    // unit ("14px", "2px") and parseFloat stops at the unit. `_pxOr`'s
    // fallback guards the transient window after a NEW token is added to
    // design/tokens.*.sh but before `phi theme set` has regenerated
    // Config/Tokens.qml on the machine: the read is `undefined`, and
    // falling back to a value that DOES resolve (another token) is safer
    // for one hot-reload than NaN propagating through layout math. `_px`
    // falls back to 0 — a sharp corner / a hairline / no padding, all
    // harmless for the same one reload, and 0 is the absence of a
    // dimension, not a design choice the I-05 ban is about.
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

    // A scale multiplier: identity by default, never a "size" in the I-05
    // sense — a dimensionless factor, same latitude as INACTIVE_OPACITY.
    function _scale(key, tokenValue) {
        var raw = root._tok(key, (tokenValue === undefined || tokenValue === null || String(tokenValue).length === 0) ? "1" : tokenValue)
        var n = parseFloat(raw)
        return (isNaN(n) || n <= 0) ? 1 : n
    }

    // Merge a Config/ThemeOverrides.qml value over a generated token.
    // Passing `null` as the fallback is how a getter asks "is this
    // overridden at all" (see accentText).
    function _tok(key, fallback) {
        var o = ThemeOverrides.value(key)
        return (o === null || o === undefined || String(o).length === 0) ? fallback : o
    }

    function _mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
    }

    // OOP-08: the settings panel's editable Theme section reads and writes
    // token overrides through Config/ThemeOverrides.qml, but it needs the
    // generated DEFAULT for each key (to seed a field, and to restore on
    // reset). Config/Tokens.qml is this file's to read, not the settings
    // panel's (S-20 contract) — so the mapping lives here.
    function tokenDefault(key) {
        switch (key) {
        case "accent": return Tokens.accent
        case "accent-fg": return Tokens.accentFg
        case "bg-0": return Tokens.bg0
        case "bg-1": return Tokens.bg1
        case "bg-2": return Tokens.bg2
        case "bg-3": return Tokens.bg3
        case "fg-0": return Tokens.fg0
        case "fg-1": return Tokens.fg1
        case "fg-2": return Tokens.fg2
        case "fg-3": return Tokens.fg3
        case "border": return Tokens.border
        case "border-strong": return Tokens.borderStrong
        case "error": return Tokens.error
        case "warn": return Tokens.warn
        case "success": return Tokens.success
        case "info": return Tokens.info
        case "font-mono": return Tokens.fontMono
        case "font-reading": return Tokens.fontReading
        case "font-ui": return Tokens.fontUi
        case "font-scale": return root._scaleString(Tokens.fontScale)
        case "space-scale": return root._scaleString(Tokens.spaceScale)
        case "radius-base": return Tokens.radiusBase
        case "radius-small": return root._numString(Tokens.radiusSmall, Tokens.radiusBase)
        case "radius-large": return root._numString(Tokens.radiusLarge, Tokens.radiusBase)
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

    // Tokens store an 8-digit colour as #rrggbbaa (CSS order, see
    // design/tokens.dark.sh's own note on PHI_OVERLAY_SCRIM), not Qt's
    // #aarrggbb — parsed by hand so a scrim's alpha byte never lands in the
    // wrong place. 6-digit values pass through with alpha 1. A malformed or
    // still-undefined value yields transparent rather than throwing.
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

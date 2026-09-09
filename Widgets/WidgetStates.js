.pragma library

// phiOS — shared state-resolution logic for Widgets/ (S-21, master plan
// §8.6: "stati trasversali obbligatori per ogni componente: default hover
// active/pressed focus disabled loading invalid"). Every widget in this
// directory resolves its own hover/press/focus/active/loading/invalid flags
// through resolve() so all ten agree on the same precedence, and reads its
// visual recipe from surfaceColors()/opacityFor()/contentColor() so the
// affordance rules (§8.6) are applied identically everywhere instead of
// once per widget — the "zero duplication inside surface class 1" goal
// §8.2 sets for this directory.
//
// A plain `.pragma library` file, not a `pragma Singleton` QML type: the
// real Quickshell `Singleton` class (`git.outfoxxed.me/quickshell/quickshell`,
// src/core/singleton.hpp) derives from `ReloadPropagator` with no default
// property, so it cannot host a nested QML child at all — confirmed by
// reading the class declaration rather than assumed, precisely because
// S-20 hit two real, unrelated Quickshell directory-scanner surprises in a
// row. A `.js` file carries no such restriction, and directory-implicit
// QML modules only ever register `*.qml` files as importable types (the
// mechanism S-20's `Tokens.example.qml` collision actually hit was a
// dotted `.qml` filename being swept in and misread as a type name — a
// different mechanism that cannot apply to a `.js` file, which never
// becomes a type at all). Every widget that calls into this file imports
// it explicitly (`import "WidgetStates.js" as WidgetStates`): unlike a
// sibling `pragma Singleton`, a `.js` library is not resolved bare.

// No design token covers opacity (design/tokens has no opacity tier); this
// is the one place that ratio lives, for the "interattivo inattivo ->
// stesso peso, opacità ridotta" affordance rule (§8.6). Not a colour, size
// or duration, so DONE WHEN's literal ban does not reach it — but it is
// still one number, kept in one place rather than repeated per widget.
var INACTIVE_OPACITY = 0.45

// Resolves the seven transverse states to exactly one, in a fixed
// precedence, so two widgets never disagree about which one wins when more
// than one flag is true at once: a disabled control never shows a hover
// colour just because the pointer happens to sit over it, and an invalid
// control still reads as invalid while it is also loading.
function resolve(flags) {
    if (!flags.enabled) return "disabled"
    if (flags.invalid) return "invalid"
    if (flags.loading) return "loading"
    if (flags.active || flags.pressed) return "active"
    if (flags.keyboardFocus) return "focus"
    if (flags.hovered) return "hover"
    return "default"
}

// §8.6: "interattivo attivo/selezionato -> inversione piena". The one
// recipe every interactive control (StyledButton, Pill, Segment, ListRow)
// reads, rather than four separate colour tables that could drift apart.
// "focus" here is the generic keyboard-focus ring these controls use;
// ListRow renders the ">" glyph instead for its own focus state, per the
// affordance rule reserving that glyph for the active input point only —
// it still calls this function for its background/border colour, the
// glyph is an addition on top, not a replacement.
//
// OOP-02 (shell restyle): the "active" case no longer fills with accent —
// accent retreated to fine detail only (titles, focus ring, the Φ agent
// processing state). "inversione piena" now means a full inversion between
// the two structural colours.
//
// `ambient` selects the surface family:
//   "panel" (default) — main background, opposite border/text; the
//     selected state inverts to an opposite block with main text.
//   "isle" (the status bar) — OOP-21: NO resting fill and no border at
//     all. A bar button is a bare opposite-coloured glyph/label on the
//     wallpaper; only the selected state paints a block, and it is the
//     same opposite-bg / main-text inversion a panel uses (item 6: the
//     bar's colours were the inverse of a panel's — they now match;
//     item 10: the isle background is gone).
function surfaceColors(appearance, resolvedState, ambient) {
    if (ambient === "isle") {
        switch (resolvedState) {
        case "active":
            return { bg: appearance.colorOpposite, fg: appearance.colorMain,
                     border: appearance.colorOpposite }
        case "invalid":
            return { bg: "transparent", fg: appearance.error, border: appearance.error }
        case "focus":
            return { bg: "transparent", fg: appearance.colorOpposite,
                     border: appearance.focusRing }
        case "hover":
            return { bg: appearance.barButtonHover, fg: appearance.colorOpposite,
                     border: "transparent" }
        default:
            return { bg: "transparent", fg: appearance.colorOpposite,
                     border: "transparent" }
        }
    }

    var surface = appearance.panelBackground
    var contrast = appearance.colorOpposite
    var hoverBg = appearance.panelHover
    switch (resolvedState) {
    case "active":
        // Full inversion — the loud, selected state.
        return { bg: contrast, fg: surface, border: contrast }
    case "invalid":
        return { bg: surface, fg: appearance.error, border: appearance.error }
    case "focus":
        // The one state that still shows accent, and only as the border.
        return { bg: surface, fg: contrast, border: appearance.focusRing }
    case "hover":
        return { bg: hoverBg, fg: contrast, border: contrast }
    default:
        // "default", "loading" and "disabled" share this base recipe —
        // opacityFor(), not colour, is what marks the latter two. It is
        // also exactly the resting Panel look: main background, opposite
        // border, opposite text.
        return { bg: surface, fg: contrast, border: contrast }
    }
}

// §8.6: "interattivo inattivo -> stesso peso del label, opacità ridotta".
// disabled and loading keep every colour surfaceColors() above returns and
// only fade — they never change hue or weight.
function opacityFor(resolvedState) {
    return (resolvedState === "disabled" || resolvedState === "loading") ? INACTIVE_OPACITY : 1.0
}

// §8.6: "label di sistema -> basso contrasto, sempre monocromo" /
// "valore/dato -> colore Tier 2 solo su soglia". Shared by StyledText and
// StyledIcon so a system label and a themed value are never picked two
// different ways. `tone` is opt-in and empty by default: the affordance
// rule is that Tier 2 is never the default, only ever something the caller
// reaches for once a real threshold is crossed — this function does not
// decide thresholds, it only renders the choice the caller already made.
function contentColor(appearance, kind, tone, invalid) {
    if (invalid)
        return appearance.error
    switch (tone) {
    case "error": return appearance.error
    case "warn": return appearance.warn
    case "success": return appearance.success
    case "info": return appearance.info
    }
    // OOP-10: "title" no longer carries accent. The user's R2 directive is
    // that accent is fine detail only — the keyboard focus ring, the Φ
    // agent processing state, a Tier-2 semantic `tone` — never a
    // structural "this is a heading" role. A title is now full-contrast
    // ink like a value, set apart by weight and size instead (StyledText /
    // StyledIcon apply a heavier font.weight for kind:"title"). "label"
    // stays low-contrast monochrome.
    return kind === "label" ? appearance.textMuted : appearance.textPrimary
}

// Shared so StyledText and StyledIcon read the same seven-step font scale
// instead of each keeping its own copy of the array.
function fontPixelSize(appearance, sizeStep) {
    var sizes = [appearance.fontSize0, appearance.fontSize1, appearance.fontSize2,
        appearance.fontSize3, appearance.fontSize4, appearance.fontSize5, appearance.fontSize6]
    var i = Math.max(0, Math.min(sizes.length - 1, sizeStep))
    return sizes[i]
}

// design/tokens.common.sh stores space-N in `ch` of font-mono, not px,
// precisely so the rhythm survives Q-N01's still-open mono-family choice —
// Appearance.qml's own comment says a caller that needs px "measures the
// font itself and multiplies". This is that arithmetic; the measurement
// itself (a `TextMetrics` on the "0" glyph, the same definition CSS's `ch`
// unit uses) lives in each widget that needs it, since neither this file
// nor a QML Singleton can host a QML object to do the measuring.
function chToPixels(chCount, chWidth) {
    return chCount * chWidth
}

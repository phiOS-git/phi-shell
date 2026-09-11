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
//   "isle" (the status bar) — features-change (item 3): a bar button now
//     has a resting surface of its own, a translucent main-coloured fill
//     (barButtonBackground) and a hairline (barButtonBorder), so each
//     control reads as a discrete button on the wallpaper. This reverses
//     OOP-21's bare-glyph rest state on the user's directive; the selected
//     state is unchanged — the same opposite-bg / main-text inversion a
//     panel uses.
function surfaceColors(appearance, resolvedState, ambient) {
    if (ambient === "isle") {
        switch (resolvedState) {
        case "active":
            // Follow-up (user, 2026-09-12): the previous pass (hover and
            // active sharing one inverted colorOpposite/colorMain sweep,
            // to fix a flicker on hover-then-click) made the two states
            // visually IDENTICAL — the user then reported that as broken
            // in its own right: unhovering an active button looked like
            // "the highlight wrongly staying applied", because hover and
            // active could no longer be told apart, plus other artifacts.
            // Reworked instead of patched: hover and active are now
            // fully separate mechanisms with no shared state, so they
            // cannot race or get confused for one another again. Active
            // no longer draws any bg/border fill at all — "use the accent
            // colour for the text and icon to show the selected state" —
            // just the resolved fg. `bg`/`border` transparent, same bare-
            // icon-on-the-isle look the resting state already has, distinct
            // from PhiAgent's own `accentWhenActive` full accent FILL
            // (Segment.qml's `stateColors` short-circuits to that before
            // ever calling this function — untouched, still its own thing).
            return { bg: "transparent", fg: appearance.accent,
                     border: "transparent" }
        case "invalid":
            return { bg: appearance.barButtonBackground, fg: appearance.error,
                     border: appearance.error }
        case "focus":
            return { bg: appearance.barButtonBackground, fg: appearance.colorOpposite,
                     border: appearance.focusRing }
        case "hover":
            // Follow-up (user, 2026-09-11): "change the hover effect,
            // instead of changing the button borders and background,
            // 'highlight' the text... and change the text color as well.
            // Do that with a transition (quick)." bg/border go transparent
            // — Widgets/Segment.qml's own sweep Rectangle carries the
            // visual highlight (direction: top-to-bottom, per a later
            // follow-up) instead of this fading in as a flat fill. `fg`
            // becomes colorMain — the full B&W inversion pair, "black on
            // light, white on dark" — kept exclusive to hover now that
            // active uses `accent` instead of this same pair (the two no
            // longer share a colour scheme, by the user's own follow-up
            // direction).
            return { bg: "transparent", fg: appearance.colorMain,
                     border: "transparent" }
        default:
            // docs/TODO.md (status-bar rework): "they should not have a
            // box button but be just icons, with hover and active
            // states." Resting state is now a bare glyph on the isle's
            // own background (Widgets/BarIsle.qml), no box, no border —
            // hover/active/focus/invalid above are unchanged and still
            // show real feedback; only the DEFAULT case loses its
            // (formerly always-on) translucent box.
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

// The status-bar rework's hand-drawn Canvas icons (SunMoonIcon, VolumeIcon,
// WifiIcon, BatteryIcon, GpuIcon) need more legible detail at a given box
// size than a Nerd Font glyph does: a font glyph is hinted for its own
// pixel grid, a stroked arc or a rounded-rect body is not. An isle Segment
// defaults to sizeStep 0 (fontSize0, 11px design/tokens.common.sh) — fine
// for a font glyph, too small for e.g. BatteryIcon's ~0.44*b-tall pill or
// WifiIcon's three nested arcs to read as anything but a smudge.
//
// Floors the box at fontSize1, not fontSize3: Widgets/Segment.qml floors
// every isle button's content height against a TextMetrics measurement of
// the mono "0" glyph AT fontSize1 (chMetrics, OOP-11 — "makes every
// Segment in an isle the same height regardless of what it holds"), and
// that measurement is not readable from here (a JS file, no TextMetrics of
// its own). fontSize1 itself is provably <= that measured height for any
// real font — a font's line height is never shorter than its own pixel
// size — so flooring here at fontSize1 keeps every icon-bearing Segment
// exactly as tall as every label-only one, with no font-metrics assumption
// needed. A larger floor (fontSize3) would read crisper still but risks
// growing icon-bearing buttons a pixel or two taller than their neighbours
// depending on the actual font's line-height ratio, unverifiable without a
// compositor (phi-shell/CLAUDE.md) — not worth that risk for a few more
// pixels of stroke width.
function drawnIconBoxSize(appearance, sizeStep) {
    return Math.max(fontPixelSize(appearance, sizeStep), appearance.fontSize1)
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

// features-change: the shared height of a single-line field or button on a
// settings row — StyledButton, SmallButton, TextField (and through them
// NumberField and ColorField) all floor their implicitHeight at this, so a
// text field and a button sitting in the same Row line up instead of the
// button towering over the field. One formula (body font size + one rhythm
// unit), not a design token — the same latitude INACTIVE_OPACITY takes.
function controlHeight(appearance, chWidth) {
    return Math.round(appearance.fontSize2 + chToPixels(appearance.space2, chWidth))
}

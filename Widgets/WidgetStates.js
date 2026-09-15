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

// Style pass 2026-09-14 (docs/TODO.md: "trigger buttons don't show
// loading states or result feedback"). Before this, `loading` and
// `disabled` shared the exact same INACTIVE_OPACITY — a button doing
// something and a button that will never do anything were visually
// IDENTICAL, which is its own version of "no loading state" even on the
// many buttons this pass has since wired a real `loading:` binding onto
// (Chat's Send, the Wi-Fi/AI-Agent/Timer refresh-and-start actions, …). A
// distinct, LESS dim ratio — still reads as "not fully interactive right
// now", but visibly different from "disabled" — needs no new animation
// mechanism and composes for free with the `Behavior on opacity` every
// widget already has, so the transition in and out of it already
// animates smoothly with zero further changes.
var LOADING_OPACITY = 0.7

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
    // ambient: "toggle" — Widgets/Toggle's own on/off switch. docs/TODO.md:
    // "switch ui element is not readable... needs to have an understandable
    // state" (explicitly not fixable by widening the track). The generic
    // B&W "inversione piena" every other selectable/active control here
    // shares (a StyledButton's `active`, a Segment's `active`, a settings
    // tab) means "this is the current selection" — a different semantic
    // than a binary preference switch's own "on", and sharing one look for
    // both made a checked Toggle hard to tell from an unchecked one at a
    // glance, since the track is only 2:1 and both states drew the exact
    // same border colour. On now fills solid with `accent` — this shell's
    // one Tier-2 colour, otherwise reserved for a real semantic threshold,
    // same reasoning `ambient: "isle"`'s own `active` case below already
    // gives for reaching for accent over B&W inversion "to show the
    // selected state" — with the knob in `accentText` (the token already
    // built to read against accent, ThemeOverrides-aware).
    //
    // Two real bugs found on real hardware in this first version, both
    // fixed here:
    //   - `hover` used `appearance.colorMain` for fg/border. `colorMain`
    //     is NOT an ink colour — Config/Appearance.qml defines it as
    //     `root.background` itself (confirmed by reading that file, not
    //     assumed; `panelBackground` is literally `root.colorMain`). Every
    //     OTHER ambient's own hover case reaches for `colorOpposite` (the
    //     real ink token) for exactly this "full contrast on hover"
    //     purpose — this one alone had the wrong one, making a hovered
    //     switch's knob and border exactly match its own panel's
    //     background: invisible.
    //   - off's track was fully `"transparent"`, which — on a dark theme,
    //     where the panel behind it is itself near-black — reads as a
    //     solid black track, visually indistinguishable from the ON
    //     state's own near-black `accentText` knob dominating the right
    //     side of the (small, 2:1) track. Net effect, reported directly:
    //     "the right part of the switch is always black" regardless of
    //     state. `offWash` (`appearance.panelHover`, the same solid
    //     background-mixed-toward-ink tint every hover wash elsewhere in
    //     this shell already uses — not a new one-off colour, and a
    //     genuine solid colour rather than an alpha blend, so it can never
    //     visually depend on whatever happens to sit behind the switch)
    //     is a permanent, low-emphasis fill — never literally transparent,
    //     and (unlike the hover bug above) never `colorMain` itself, so it
    //     can never blend into the very panel it sits on.
    if (ambient === "toggle") {
        var offWash = appearance.panelHover
        switch (resolvedState) {
        case "active":
            return { bg: appearance.accent, fg: appearance.accentText, border: appearance.accent }
        case "invalid":
            return { bg: offWash, fg: appearance.error, border: appearance.error }
        case "focus":
            return { bg: offWash, fg: appearance.colorOpposite, border: appearance.focusRing }
        case "hover":
            return { bg: offWash, fg: appearance.colorOpposite, border: appearance.colorOpposite }
        default:
            return { bg: offWash, fg: appearance.textMuted, border: appearance.textMuted }
        }
    }

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

    // `ambient: "tab"` — a section-switcher grammar, deliberately distinct
    // from a "panel" push button's full inversion: a tab never reads as a
    // button being pressed, since selecting it is a navigation state, not a
    // momentary action. No resting box, a hover wash (same recipe an
    // Accordion header uses), and the current tab marked by accent text —
    // the indicator bar itself is drawn by Widgets/TabButton.qml, since its
    // edge depends on the strip's orientation, which this file cannot know.
    if (ambient === "tab") {
        switch (resolvedState) {
        case "active":
            return { bg: "transparent", fg: appearance.accent, border: "transparent" }
        case "invalid":
            return { bg: "transparent", fg: appearance.error, border: "transparent" }
        case "focus":
            return { bg: "transparent", fg: appearance.colorOpposite, border: appearance.focusRing }
        case "hover":
            return { bg: appearance.panelHover, fg: appearance.colorOpposite, border: "transparent" }
        default:
            return { bg: "transparent", fg: appearance.textMuted, border: "transparent" }
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
// disabled and loading both keep every colour surfaceColors() above
// returns and only fade — they never change hue or weight — but no longer
// fade to the SAME degree (see LOADING_OPACITY's own comment above).
function opacityFor(resolvedState) {
    if (resolvedState === "loading") return LOADING_OPACITY
    if (resolvedState === "disabled") return INACTIVE_OPACITY
    return 1.0
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

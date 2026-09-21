.pragma library

// Shared state-resolution logic for Widgets/. Every widget in this
// directory resolves its own hover/press/focus/active/loading/invalid flags
// through resolve() so they all agree on the same precedence, and reads its
// visual recipe from surfaceColors()/opacityFor()/contentColor() so the
// affordance rules are applied identically everywhere instead of once per
// widget.
//
// A plain `.pragma library` file, not a `pragma Singleton` QML type: the
// real Quickshell `Singleton` class derives from `ReloadPropagator` with no
// default property, so it cannot host a nested QML child at all. A `.js`
// file carries no such restriction, and directory-implicit QML modules
// only ever register `*.qml` files as importable types — a `.js` file
// never becomes a type at all, so it cannot collide with one the way a
// dotted `.qml` filename can be swept in and misread as a type name. Every
// widget that calls into this file imports it explicitly
// (`import "WidgetStates.js" as WidgetStates`): unlike a sibling
// `pragma Singleton`, a `.js` library is not resolved bare.

// No design token covers opacity: a disabled control keeps its exact
// colours and only fades, so this is the one place that ratio lives —
// still one number, kept in one place rather than repeated per widget.
var INACTIVE_OPACITY = 0.45

// A distinct, LESS dim ratio than INACTIVE_OPACITY — a button doing
// something and a button that will never do anything should not be
// visually identical. Needs no new animation mechanism and composes for
// free with the `Behavior on opacity` every widget already has.
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

// The one recipe every interactive control (StyledButton, Toggle, Segment,
// ListRow) reads for its active/selected look, rather than four separate
// colour tables that could drift apart. "focus" here is the generic
// keyboard-focus ring these controls use; ListRow renders the ">" glyph
// instead for its own focus state, reserving that glyph for the active
// input point only — it still calls this function for its
// background/border colour, the glyph is an addition on top, not a
// replacement.
//
// The "active" case fills with the two structural colours in full
// inversion, not accent — accent is fine detail only (titles, focus ring,
// the Φ agent processing state).
//
// `ambient` selects the surface family:
//   "panel" (default) — main background, opposite border/text; the
//     selected state inverts to an opposite block with main text.
//   "isle" (the status bar) — a bar button has a resting surface of its
//     own, a translucent main-coloured fill (barButtonBackground) and a
//     hairline (barButtonBorder), so each control reads as a discrete
//     button on the wallpaper. The selected state is the same
//     opposite-bg / main-text inversion a panel uses.
function surfaceColors(appearance, resolvedState, ambient, checked) {
    // ambient: "toggle" — Widgets/Toggle's own on/off switch. `checked`
    // decides the track's fill alone: `offBg` off, `accent` — this shell's
    // one Tier-2 colour, otherwise reserved for a real semantic threshold —
    // on. Every other value here (knob fill/border, track border) stays the
    // same token regardless of `checked`, except "invalid", so on/off reads
    // as one colour change. `resolvedState` alone can't carry that: "disabled"
    // and "loading" outrank "active" in resolve(), so a disabled-but-on
    // control (Night Shift under a schedule) still shows accent, dimmed.
    // Hover has no colour step of its own — the knob's hover affordance is
    // geometric (Toggle.qml).
    //
    // `offBg` is never literally transparent: on a near-black dark panel a
    // transparent track is indistinguishable from a resting knob on it. The
    // knob also needs its own `borderStrong` stroke: `accent` sits as far
    // from bg-0 as `offBg` sits close to it, so no flat fill reads against
    // both track colours at once.
    if (ambient === "toggle") {
        var offBg = appearance.panelHover
        switch (resolvedState) {
        case "invalid":
            return { bg: offBg, fg: appearance.error, border: appearance.error }
        case "focus":
            // Reads `checked` too, though unreachable today — "active"
            // (checked) outranks "focus" in resolve().
            return { bg: checked ? appearance.accent : offBg,
                     fg: appearance.colorOpposite, border: appearance.focusRing }
        default:
            // default/hover/active/loading/disabled all land here and read
            // the track fill straight off `checked` (see comment above).
            return { bg: checked ? appearance.accent : offBg,
                     fg: appearance.colorOpposite, border: appearance.borderStrong }
        }
    }

    // `ambient: "shaded"` — makes real use of `surface1/2/3` (bg-1/2/3) and
    // `border`/`borderStrong` instead of falling through to the generic
    // block below, which is a full `colorMain`/`colorOpposite` B&W
    // inversion. A separate branch, not an edit to that block: Widgets/
    // Checkbox, Widgets/Radio and Widgets/ListRow call surfaceColors() with
    // no ambient at all and get the unchanged generic block; only
    // Widgets/Panel, Widgets/SmallButton, Widgets/StyledButton and
    // Widgets/Segment's own default opt in to "shaded".
    //
    // `active` (selected) does not swap the whole surface to the opposite
    // ink colour — it rises one more shade (surface3, the most elevated
    // step) and gets an accent-coloured edge, so accent stays fine detail
    // only (the edge, not a fill) even for the one state that most wants
    // to stand out. `focus` keeps the pre-existing accent ring convention.
    if (ambient === "shaded") {
        switch (resolvedState) {
        case "active":
            return { bg: appearance.surface3, fg: appearance.textPrimary, border: appearance.accent }
        case "invalid":
            return { bg: appearance.surface1, fg: appearance.error, border: appearance.error }
        case "focus":
            return { bg: appearance.surface1, fg: appearance.textPrimary, border: appearance.focusRing }
        case "hover":
            return { bg: appearance.surface2, fg: appearance.textPrimary, border: appearance.borderStrong }
        default:
            return { bg: appearance.surface1, fg: appearance.textPrimary, border: appearance.border }
        }
    }

    if (ambient === "isle") {
        switch (resolvedState) {
        case "active":
            // Hover and active are fully separate mechanisms with no
            // shared state — sharing one inverted colorOpposite/colorMain
            // sweep between them makes unhovering an active button read as
            // the highlight wrongly staying applied, since the two states
            // become indistinguishable. Active draws no bg/border fill at
            // all, just the resolved fg in accent — `bg`/`border`
            // transparent, the same bare-icon-on-the-isle look the resting
            // state has, distinct from PhiAgent's own `accentWhenActive`
            // full accent FILL (Segment.qml's `stateColors` short-circuits
            // to that before ever calling this function).
            return { bg: "transparent", fg: appearance.accent,
                     border: "transparent" }
        case "invalid":
            return { bg: appearance.barButtonBackground, fg: appearance.error,
                     border: appearance.error }
        case "focus":
            return { bg: appearance.barButtonBackground, fg: appearance.colorOpposite,
                     border: appearance.focusRing }
        case "hover":
            // bg/border stay transparent — Widgets/Segment.qml's own sweep
            // Rectangle carries the visual highlight instead of this
            // fading in as a flat fill. `fg` becomes colorMain — the full
            // B&W inversion pair — kept exclusive to hover now that active
            // uses `accent` instead of this same pair, so the two states
            // no longer share a colour scheme.
            return { bg: "transparent", fg: appearance.colorMain,
                     border: "transparent" }
        default:
            // A bare glyph on the isle's own background (Widgets/BarIsle.qml),
            // no box, no border — hover/active/focus/invalid above are
            // unchanged and still show real feedback; only the DEFAULT
            // case has no translucent box.
            return { bg: "transparent", fg: appearance.colorOpposite,
                     border: "transparent" }
        }
    }

    // `ambient: "workspace"` — a workspace-square-specific variant of
    // "isle" above: a list of clickable squares showing the workspace
    // number with a thin border, no background, and inverted colours when
    // selected. Same bar-button grammar in every other respect (Segment's
    // own `_bar` flag keeps the mono font / tight isle padding / hover-sweep
    // it shares with "isle") — that differs in exactly the two things
    // "isle" above deliberately does NOT have: a real resting BORDER
    // (every other isle button drops its resting border/background
    // entirely) and a real INVERTED FILL on active (every other isle
    // button's own active state is bare accent text with no fill —
    // Segment.qml's own `contentColor` carves this ambient out of that
    // override so `stateColors.fg` below is actually used). The width
    // increase itself is Bar/modules/Workspaces.qml's own job
    // (`Segment.widthBoost`) — this file only supplies colour.
    if (ambient === "workspace") {
        switch (resolvedState) {
        case "active":
            return { bg: appearance.colorOpposite, fg: appearance.colorMain, border: appearance.colorOpposite }
        case "invalid":
            return { bg: "transparent", fg: appearance.error, border: appearance.error }
        case "focus":
            return { bg: "transparent", fg: appearance.colorOpposite, border: appearance.focusRing }
        case "hover":
            return { bg: "transparent", fg: appearance.colorMain, border: appearance.colorOpposite }
        default:
            return { bg: "transparent", fg: appearance.colorOpposite, border: appearance.border }
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

    // `ambient: "powerPill"` — Dialogs/PowerActionsRow's own pill row: a
    // horizontal row of icon+label actions floating directly on the
    // wallpaper/scrim, one of them marked with a solid accent fill. The
    // accent FILL on `active` is a deliberate exception to this shell's
    // usual "accent is fine detail only" rule — the same exception this
    // file's own `ambient: "toggle"` carries for its own checked/on fill,
    // for the same reason: one real state that has to read at a glance,
    // not a structural "this is a heading" role. Every other state stays
    // bare (no resting box at all, unlike `toggle`'s own off state, which
    // keeps a permanent `offBg` fill) — plain icon+text on the wallpaper,
    // nothing boxed.
    //
    // The caller (PowerActionsRow.qml) passes its own real keyboard-focus
    // flag in as `active`, not `keyboardFocus` — so `resolvedState` here is
    // never actually "focus" for this ambient, only "active"/"hover"/
    // "invalid"/default. No `case "focus"` in this block on purpose: it
    // would be genuinely unreachable dead code, not a harmless spare.
    //
    // `hover` stays this generic wash recipe (`panelHover` bg, opposite
    // fg) as the ambient's own default, but PowerActionsRow does NOT read
    // it: that caller overrides the hover fill with each action's own
    // semantic tone (`_toneFor`/`_toneTextFor` in the row's file) so a
    // shutdown pill hovers red, a logout amber, &c. — an id both this
    // ambient and the parity with the status row reject (no glyph or pill
    // carries a per-action colour by default; the row itself opts in
    // per-action on hover).
    if (ambient === "powerPill") {
        switch (resolvedState) {
        case "active":
            return { bg: appearance.accent, fg: appearance.accentText, border: appearance.accent }
        case "invalid":
            return { bg: "transparent", fg: appearance.error, border: "transparent" }
        case "hover":
            return { bg: appearance.panelHover, fg: appearance.colorOpposite, border: "transparent" }
        default:
            return { bg: "transparent", fg: appearance.textMuted, border: "transparent" }
        }
    }

    // `ambient: "list"` — a thinner style for a status-bar-overlay device
    // list: a list of texts with the "highlight" hover and selection, the
    // same effect the runner bar uses. No resting or hover fill at all — a
    // plain text row — and `active`/`focus` use `selectionBackground`/
    // `selectionText`, the same pair Launcher.qml's own result-row
    // highlight reads, so a selected ListRow entry matches the runner
    // bar's own effect by construction, not by a separately chosen colour
    // that could drift from it. The opacity half of the hover effect is
    // deliberately NOT here — ListRow.qml itself resolves that (its own
    // row-level dimming), since it is a presentation choice about THIS
    // widget specifically, not a colour recipe shared across ambients the
    // way bg/fg/border are.
    if (ambient === "list") {
        switch (resolvedState) {
        case "active":
            return { bg: appearance.selectionBackground, fg: appearance.selectionText, border: "transparent" }
        case "invalid":
            return { bg: "transparent", fg: appearance.error, border: "transparent" }
        case "focus":
            return { bg: appearance.selectionBackground, fg: appearance.selectionText, border: "transparent" }
        case "hover":
            return { bg: "transparent", fg: appearance.colorOpposite, border: "transparent" }
        default:
            return { bg: "transparent", fg: appearance.colorOpposite, border: "transparent" }
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

// disabled and loading both keep every colour surfaceColors() above
// returns and only fade — they never change hue or weight — but not to the
// SAME degree (see LOADING_OPACITY's own comment above).
function opacityFor(resolvedState) {
    if (resolvedState === "loading") return LOADING_OPACITY
    if (resolvedState === "disabled") return INACTIVE_OPACITY
    return 1.0
}

// Shared by StyledText and StyledIcon so a system label and a themed value
// are never picked two different ways. `tone` is opt-in and empty by
// default: a semantic colour is never the default, only ever something the
// caller reaches for once a real threshold is crossed — this function does
// not decide thresholds, it only renders the choice the caller already
// made.
function contentColor(appearance, kind, tone, invalid) {
    if (invalid)
        return appearance.error
    switch (tone) {
    case "error": return appearance.error
    case "warn": return appearance.warn
    case "success": return appearance.success
    case "info": return appearance.info
    }
    // "title" does not carry accent — accent is fine detail only (the
    // keyboard focus ring, the Φ agent processing state, a semantic
    // `tone`), never a structural "this is a heading" role. A title is
    // full-contrast ink like a value, set apart by weight and size instead
    // (StyledText / StyledIcon apply a heavier font.weight for
    // kind:"title"). "label" stays low-contrast monochrome.
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
// the mono "0" glyph AT fontSize1 (chMetrics — makes every Segment in an
// isle the same height regardless of what it holds), and that measurement
// is not readable from here (a JS file, no TextMetrics of its own).
// fontSize1 itself is provably <= that measured height for any
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

// design/tokens.common.sh stores space-N in `ch` of font-mono, not px, so
// the rhythm survives whichever mono family a theme ends up picking — a
// caller that needs px measures the font itself and multiplies. This is
// that arithmetic; the measurement itself (a `TextMetrics` on the "0"
// glyph, the same definition CSS's `ch` unit uses) lives in each widget
// that needs it, since neither this file nor a QML Singleton can host a
// QML object to do the measuring.
function chToPixels(chCount, chWidth) {
    return chCount * chWidth
}

// The shared height of a single-line field or button on a settings row —
// StyledButton, SmallButton, TextField (and through them NumberField and
// ColorField) all floor their implicitHeight at this, so a text field and
// a button sitting in the same Row line up instead of the button towering
// over the field. One formula (body font size + one rhythm unit), not a
// design token.
function controlHeight(appearance, chWidth) {
    return Math.round(appearance.fontSize2 + chToPixels(appearance.space2, chWidth))
}

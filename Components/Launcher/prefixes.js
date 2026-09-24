.pragma library

// The runner-bar prefix feature's shell-side table. This file only decides
// what a locked prefix LOOKS like (its chip label and highlight colour) —
// what a keyword actually DOES is phi's own decision,
// internal/query/query.go's prefixProviders map. The two lists must stay
// in sync BY HAND: a keyword added to one belongs in the other too. There
// is no shared source between the Go binary and this QML process to
// generate either from.
//
// tone is one of Config.Appearance's five semantic colour tokens — design
// tokens are the only source of colour, this file never invents a hex
// value. Grouped by what kind of action the keyword performs, not one
// distinct hue per keyword: there are only five semantic tones and more
// keywords than that. "accent" is included even though Widgets/
// WidgetStates.js's own contentColor() deliberately does NOT treat accent
// as a valid StyledText/StyledIcon tone (accent is fine detail only) —
// this file's color()/textColor() below read Config.Appearance.accent
// directly instead of going through that resolver, which is a separate,
// narrower rule about what StyledText's own `tone` property accepts, not
// a ban on using the accent token elsewhere.
// hint is what the empty-input, locked-tag result list shows under the input
// (Launcher.qml's per-tag hint state) — phi still decides what to DO with
// whatever gets typed, this is only the shell's own placeholder prompt.
var PREFIXES = [
    { key: "web",     label: "Web",       tone: "info", glyph: 0xF059F, hint: "Type to search the web" },
    { key: "wiki",    label: "Wikipedia", tone: "info", glyph: 0xF05AC, hint: "Type to search Wikipedia" },
    { key: "yt",      label: "YouTube",   tone: "info", glyph: 0xF05C3, hint: "Type to search YouTube" },
    { key: "arch",    label: "Arch Wiki", tone: "info", glyph: 0xF303, hint: "Type to search the Arch Wiki" },
    { key: "rddt",    label: "Reddit",    tone: "info", glyph: 0xF044D, hint: "Type to search Reddit" },
    { key: "ask",     label: "Ask AI",    tone: "accent", glyph: 0xF167A, hint: "Type a question for the agent" },
    { key: "math",    label: "Math",      tone: "accent", glyph: 0xF00EC, hint: "Type an expression" },
    { key: "convert", label: "Convert",   tone: "accent", glyph: 0xF04E1, hint: "Type a conversion, e.g. 5 km to mi" },
    { key: "file",    label: "File",      tone: "success", glyph: 0xF0224, hint: "Type a file name" },
    { key: "app",     label: "App",       tone: "success", glyph: 0xF003B, hint: "Type an app name" },
    { key: "run",     label: "Run",       tone: "success", glyph: 0xF018D, hint: "Type a command to run" },
    { key: "phi",     label: "phi",       tone: "warn", glyph: 0, hint: "Type a phi command" },
    // Clipboard history: three spellings, one category (Go routes all three
    // to the clipboard provider).
    { key: "copy",    label: "Clipboard", tone: "success", glyph: 0xF0147, hint: "Clipboard history is empty" },
    { key: "clip",    label: "Clipboard", tone: "success", glyph: 0xF0147, hint: "Clipboard history is empty" },
    { key: "cp",      label: "Clipboard", tone: "success", glyph: 0xF0147, hint: "Clipboard history is empty" },
]

// The runner's Φ becomes the locked tag's glyph (Nerd Font codepoints; 0
// keeps Φ, as the `phi` tag does).
function glyph(key) {
    var p = find(key)
    return p && p.glyph ? String.fromCodePoint(p.glyph) : ""
}

function find(key) {
    for (var i = 0; i < PREFIXES.length; i++) {
        if (PREFIXES[i].key === key) return PREFIXES[i]
    }
    return null
}

// The empty-input hint for a locked tag; "" for an unknown key (Launcher.qml
// only ever locks a key detect() found, so this is just a safe fallback).
function hint(key) {
    var p = find(key)
    return p ? p.hint : ""
}

// detect reports the known prefix keyword leading text, case-insensitively.
// The text (trimmed of outer whitespace) must either equal the keyword
// exactly — Tab locking before any remainder is typed — or start with
// "keyword ", matching every routed Go provider's own "keyword + space"
// convention (internal/query/*.go). Called only from Launcher.qml's
// Keys.onTabPressed.
function detect(text) {
    var trimmed = text.trim().toLowerCase()
    for (var i = 0; i < PREFIXES.length; i++) {
        var key = PREFIXES[i].key
        if (trimmed === key || trimmed.indexOf(key + " ") === 0) {
            return key
        }
    }
    return ""
}

// color/textColor resolve a locked prefix's chip fill and matching
// readable-on-it text colour. appearance is Config.Appearance, passed in
// rather than imported — this is a plain `.pragma library` JS file, the
// same shape Widgets/WidgetStates.js already uses for the identical
// reason (its own header explains why a JS library cannot import a QML
// singleton).
function color(appearance, key) {
    var p = find(key)
    switch (p ? p.tone : "") {
    case "accent": return appearance.accent
    case "warn": return appearance.warn
    case "success": return appearance.success
    case "info": return appearance.info
    default: return appearance.border
    }
}

function textColor(appearance, key) {
    var p = find(key)
    switch (p ? p.tone : "") {
    case "accent": return appearance.accentText
    case "warn": return appearance.warnText
    case "success": return appearance.successText
    case "info": return appearance.infoText
    default: return appearance.textPrimary
    }
}

.pragma library

// phiOS — Launcher/prefixes.js. The runner-bar prefix feature's shell-side
// table (docs/TODO.md: "Add prefix feature to the runner bar... each
// should be configured with a color code"). This file only decides what a
// locked prefix LOOKS like (its chip label and highlight colour) — what a
// keyword actually DOES is phi's own decision, internal/query/query.go's
// prefixProviders map. The two lists must stay in sync BY HAND: a keyword
// added to one belongs in the other too. There is no shared source between
// the Go binary and this QML process to generate either from.
//
// tone is one of Config.Appearance's five semantic colour tokens (rule 6:
// design tokens are the only source of colour — this file never invents a
// hex value). Grouped by what kind of action the keyword performs, not one
// distinct hue per keyword: there are only five semantic tones and, per
// the entry's own "more prefixes will be added with time," eventually more
// keywords than that. "accent" is included even though Widgets/
// WidgetStates.js's own contentColor() deliberately does NOT treat accent
// as a valid StyledText/StyledIcon tone (OOP-10: accent retreated to "fine
// detail only") — this file's color()/textColor() below read
// Config.Appearance.accent directly instead of going through that
// resolver, which is a separate, narrower rule about what StyledText's own
// `tone` property accepts, not a ban on using the accent token elsewhere.
var PREFIXES = [
    { key: "web",     label: "Web",       tone: "info" },
    { key: "wiki",    label: "Wikipedia", tone: "info" },
    { key: "yt",      label: "YouTube",   tone: "info" },
    { key: "arch",    label: "Arch Wiki", tone: "info" },
    { key: "rddt",    label: "Reddit",    tone: "info" },
    { key: "ask",     label: "Ask AI",    tone: "accent" },
    { key: "math",    label: "Math",      tone: "accent" },
    { key: "convert", label: "Convert",   tone: "accent" },
    { key: "file",    label: "File",      tone: "success" },
    { key: "app",     label: "App",       tone: "success" },
    { key: "run",     label: "Run",       tone: "success" },
    { key: "phi",     label: "phi",       tone: "warn" },
]

function find(key) {
    for (var i = 0; i < PREFIXES.length; i++) {
        if (PREFIXES[i].key === key) return PREFIXES[i]
    }
    return null
}

// detect reports the known prefix keyword leading text, case-insensitively,
// only once there is at least one more character after the separating
// space — "web" alone is not yet a request to lock, matching every routed
// Go provider's own "keyword + space" convention (internal/query/*.go).
function detect(text) {
    var lower = text.toLowerCase()
    for (var i = 0; i < PREFIXES.length; i++) {
        var lead = PREFIXES[i].key + " "
        if (lower.indexOf(lead) === 0 && text.length > lead.length) {
            return PREFIXES[i].key
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

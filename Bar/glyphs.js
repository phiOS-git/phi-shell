.pragma library

// phiOS — Bar/glyphs.js (OOP-11, shell restyle R2). Every Nerd Font symbol
// codepoint the status bar uses, in ONE place: the user's directive is that
// each right-isle button shows "an icon and next to it the text content",
// which turns three unverified glyphs (btop, the notification bell) into a
// dozen. Centralised here so a "renders as a box on real hardware" report
// is one fix, not one per module file.
//
// Codepoints are the Material Design Icons block of "Symbols Nerd Font
// Mono" (design/tokens.common.sh PHI_FONT_SYMBOL), PUA range U+F0000+.
// String.fromCodePoint, not a literal glyph in the source, because the
// editor tooling in this loop has dropped raw PUA characters before now.
//
// UNVERIFIED against the font on real hardware — flagged for the screenshot
// pass. The modules always render the value text too, so a missing glyph
// degrades to "a box next to a readable number", never to nothing.

function _c(cp) { return String.fromCodePoint(cp) }

var wifi            = _c(0xF05A9)   // nf-md-wifi
var wifiOff         = _c(0xF05AA)   // nf-md-wifi_off
var wifiAlert       = _c(0xF16B5)   // nf-md-wifi_alert
var bluetooth       = _c(0xF00AF)   // nf-md-bluetooth
var bluetoothOff    = _c(0xF00B2)   // nf-md-bluetooth_off
var bluetoothConn   = _c(0xF00B1)   // nf-md-bluetooth_connect
var vpn             = _c(0xF0582)   // nf-md-vpn
var vpnOff          = _c(0xF0591)   // nf-md-network_off  (tailscale down)
var battery         = _c(0xF0079)   // nf-md-battery (full)
var batteryCharging = _c(0xF0084)   // nf-md-battery_charging
var batteryAlert    = _c(0xF0083)   // nf-md-battery_alert
var volume          = _c(0xF057E)   // nf-md-volume_high
var volumeMute      = _c(0xF075F)   // nf-md-volume_mute
var brightness      = _c(0xF00DF)   // nf-md-brightness_6
var gpu             = _c(0xF08AE)   // nf-md-expansion_card
var bell            = _c(0xF009A)   // nf-md-bell
var bellOff         = _c(0xF009B)   // nf-md-bell_off
var monitor         = _c(0xF0A07)   // nf-md-monitor_dashboard (btop workspace icon, ADR 134)
var steam           = _c(0xF04D3)   // nf-md-steam (Steam workspace icon, ADR 134) — was 0xF03F7,
                                     // which is actually nf-md-phone_incoming (docs/TODO.md:
                                     // "steam icon in the status bar is using a phone glyph"),
                                     // confirmed against nerd-fonts' own glyphnames.json
var console         = _c(0xF018D)   // nf-md-console (scratchpad toggle icon) — was
                                     // 0xF0295, which is actually nf-md-function
                                     // (docs/TODO.md: "there is an icon 'f' in the
                                     // status bar ... that does nothing" — same
                                     // wrong-codepoint mistake as the steam glyph
                                     // above, and the same fix: confirmed against
                                     // nerd-fonts' own glyphnames.json)
var clipboard       = _c(0xF0147)   // nf-md-clipboard
var power           = _c(0xF0425)   // nf-md-power (left-isle power icon)
var lock            = _c(0xF033E)   // nf-md-lock (power menu: Lock)
var powerSleep      = _c(0xF0904)   // nf-md-power_sleep (power menu: Suspend) — confirmed
                                     // 2026-09-14 against a fresh copy of nerd-fonts' own
                                     // glyphnames.json (not recalled, not retried-until-it-
                                     // looked-right the way the prior session's live lookups
                                     // did): "power_sleep" is a real, exact-named MDI icon.
var timer           = _c(0xF051B)   // nf-md-timer_outline (Bar/modules/Timer.qml —
                                     // covers both timers and alarms, Services/Timers.qml's
                                     // own single shared mechanism) — confirmed 2026-09-14
                                     // against a live fetch of nerd-fonts' own
                                     // glyphnames.json (md-timer_outline: f051b), not
                                     // recalled, per this file's own standing rule after
                                     // three past wrong-codepoint incidents (steam,
                                     // console/function, and the missing hibernate icon).
var stopwatch       = _c(0xF13AB)   // nf-md-timer (Bar/modules/Stopwatch.qml) — the FILLED
                                     // variant of the same base icon `timer` above already
                                     // uses outlined for the countdown timer/alarm concept;
                                     // MDI's "timer" (not "-outline") is the analog-stopwatch
                                     // pictogram, a deliberately related-but-distinct glyph
                                     // for a related-but-distinct feature. Confirmed 2026-09-14
                                     // against a live fetch of nerd-fonts' own glyphnames.json
                                     // (md-timer: f13ab) AND checked present in the installed
                                     // font's own charset (`fc-query`'s dump for
                                     // SymbolsNerdFontMono-Regular.ttf covers f0001-f1af0,
                                     // which contains this codepoint) — this file's standing
                                     // rule after three past wrong-codepoint incidents.
var restart         = _c(0xF0709)   // nf-md-restart (power menu: Reboot) — same verification.
                                     // NO exact "hibernate" icon exists anywhere in nerd-fonts'
                                     // own glyph set (checked systematically against a dozen
                                     // candidate names — sleep, power_standby, moon, bed, etc.
                                     // all exist but none is named "hibernate").
var hibernate       = _c(0xF0717)   // nf-md-snowflake (power menu: Hibernate) — the deliberate
                                     // substitute for the missing "hibernate" name above: a
                                     // "frozen" pictogram is the same convention several real
                                     // desktop environments already use for this action, and it
                                     // reads as clearly distinct from `powerSleep`'s crescent
                                     // moon (already spoken for by Suspend on this same menu).
                                     // Confirmed 2026-09-15 against a fresh fetch of nerd-fonts'
                                     // own glyphnames.json (md-snowflake: f0717), inside the
                                     // f0001-f1af0 range this file already knew the installed
                                     // SymbolsNerdFontMono-Regular.ttf covers (see `stopwatch`
                                     // above) — then checked rendering with a real screenshot
                                     // of the power menu, not assumed.

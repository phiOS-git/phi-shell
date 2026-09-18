.pragma library

// Every Nerd Font symbol codepoint the status bar uses, in ONE place, so a
// "renders as a box on real hardware" report is one fix, not one per
// module file.
//
// Codepoints are the Material Design Icons block of "Symbols Nerd Font
// Mono", PUA range U+F0000+. String.fromCodePoint, not a literal glyph in
// the source, because the editor tooling in this loop has dropped raw PUA
// characters before now.
//
// Every codepoint here is checked against nerd-fonts' own glyphnames.json
// rather than recalled from memory — this file has shipped more than one
// wrong guessed codepoint before, and a wrong PUA codepoint silently
// renders as a box with no error.
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
var tailscale       = _c(0xF06F3)   // nf-md-network
// var vpnOff          = _c(0xF0591)   // nf-md-network_off  (tailscale down)
var vpn             = _c(0xF0582)   // nf-md-vpn
var firewall        = _c(0xF07FE)   // nf-md-wall
var battery         = _c(0xF0079)   // nf-md-battery (full)
var batteryCharging = _c(0xF0084)   // nf-md-battery_charging
var batteryAlert    = _c(0xF0083)   // nf-md-battery_alert
var volume          = _c(0xF057E)   // nf-md-volume_high
var volumeMute      = _c(0xF075F)   // nf-md-volume_mute
var brightness      = _c(0xF00DF)   // nf-md-brightness_6
var gpu             = _c(0xF08AE)   // nf-md-expansion_card
var bell            = _c(0xF009A)   // nf-md-bell
var bellOff         = _c(0xF009B)   // nf-md-bell_off
var monitor         = _c(0xF0A07)   // nf-md-monitor_dashboard (btop workspace icon)
var steam           = _c(0xF04D3)   // nf-md-steam (Steam workspace icon) — was 0xF03F7,
                                     // which is actually nf-md-phone_incoming; a wrong
                                     // guessed codepoint, corrected against nerd-fonts'
                                     // own glyphnames.json
var console         = _c(0xF018D)   // nf-md-console (scratchpad toggle icon) — was
                                     // 0xF0295, which is actually nf-md-function; the
                                     // same wrong-codepoint mistake as `steam` above,
                                     // and the same fix
var clipboard       = _c(0xF0147)   // nf-md-clipboard
var power           = _c(0xF0425)   // nf-md-power (left-isle power icon)
var lock            = _c(0xF033E)   // nf-md-lock (power menu: Lock)
var powerSleep      = _c(0xF0904)   // nf-md-power_sleep (power menu: Suspend)
var timer           = _c(0xF051B)   // nf-md-timer_outline (Bar/modules/Timer.qml —
                                     // covers both timers and alarms, Services/Timers.qml's
                                     // own single shared mechanism)
var stopwatch       = _c(0xF13AB)   // nf-md-timer (Bar/modules/Stopwatch.qml) — the FILLED
                                     // variant of the same base icon `timer` above already
                                     // uses outlined for the countdown timer/alarm concept;
                                     // MDI's "timer" (not "-outline") is the analog-stopwatch
                                     // pictogram, a deliberately related-but-distinct glyph
                                     // for a related-but-distinct feature.
var restart         = _c(0xF0709)   // nf-md-restart (power menu: Reboot). NO exact
                                     // "hibernate" icon exists anywhere in nerd-fonts'
                                     // own glyph set (checked systematically against a
                                     // dozen candidate names — sleep, power_standby,
                                     // moon, bed, etc. all exist but none is named
                                     // "hibernate").
var logout          = _c(0xF0343)   // nf-md-logout (power menu / power pill row: Log out)
var hibernate       = _c(0xF0717)   // nf-md-snowflake (power menu: Hibernate) — the
                                     // deliberate substitute for the missing "hibernate"
                                     // name above: a "frozen" pictogram is the same
                                     // convention several real desktop environments
                                     // already use for this action, and it reads as
                                     // clearly distinct from `powerSleep`'s crescent
                                     // moon (already spoken for by Suspend on this same
                                     // menu).
var copy            = _c(0xF018F)   // nf-md-content_copy (chat bubble: copy this message)

// Bar/modules/Media.qml + the shared MediaControls section and the status
// card's media section. The bar glyph shows the current STATE (play while
// playing, pause while paused) and the module hides entirely while no
// player is connected, so there is no idle placeholder. The popout's
// play/pause button uses the same two glyphs the other way round (what
// pressing it will do). The media section's queue-state buttons use
// shuffle / repeat / repeatOnce when the player supports them (gated on
// screen; UNVERIFIED against the font on real hardware — flagged for the
// screenshot pass). No text label next to the bar glyph, so a wrong
// codepoint here is a bare box.
var play            = _c(0xF040A)   // nf-md-play (bar: playing state / popout: play action)
var pause           = _c(0xF03E4)   // nf-md-pause (bar: paused state / popout: pause action)
var skipPrev        = _c(0xF04AE)   // nf-md-skip_previous (MediaControls: previous track)
var skipNext        = _c(0xF04AD)   // nf-md-skip_next (MediaControls: next track)
var shuffle         = _c(0xF049D)   // nf-md-shuffle (MediaControls: shuffled queue)
var repeat          = _c(0xF0456)   // nf-md-repeat (MediaControls: repeat queue/playlist)
var repeatOnce      = _c(0xF0458)   // nf-md-repeat_once (MediaControls: repeat current track)

// Bar/modules/Screenshot.qml + its popout — also glyph-only on the bar, so
// the same wrong-codepoint risk applies.
var camera          = _c(0xF0100)   // nf-md-camera (screenshot icon, idle)
var crop            = _c(0xF019E)   // nf-md-crop (awaiting an area selection; popout "Capture area")
var recordRec       = _c(0xF044B)   // nf-md-record_rec (screen recording)
var screenshotFull  = _c(0xF0E51)   // nf-md-monitor_screenshot (popout: fullscreen capture)
var screenshotWin   = _c(0xF05B2)   // nf-md-window_restore (popout: active-window capture)
var ocr             = _c(0xF113D)   // nf-md-text_recognition (popout: OCR a region)
var qr              = _c(0xF0432)   // nf-md-qrcode (popout: scan a QR code)

// Bar/modules/{Lens,StatusMenu,Stats}.qml — none of these three modules
// render a text label next to the glyph, so a wrong codepoint here is a
// bare box with no readable fallback next to it.
var lens            = _c(0xF0349)   // nf-md-magnify (Bar/modules/Lens.qml — opens the runner bar)
var settings        = _c(0xF0493)   // nf-md-cog (Bar/modules/StatusMenu.qml — opens the "status overlay")
var stats           = _c(0xF0128)   // nf-md-chart_bar (Bar/modules/Stats.qml — opens the "stats overlay")

// A fitting icon for each of the status overlay's six tiling-mode buttons,
// centred above the text.
var tilingXScroll   = _c(0xF084E)   // nf-md-arrow_expand_horizontal — a horizontal scrolling strip
var tilingYScroll   = _c(0xF084F)   // nf-md-arrow_expand_vertical — the vertical counterpart above
var tilingTile      = _c(0xF0570)   // nf-md-view_grid — the classic tiled-grid pictogram
var tilingCenter    = _c(0xF0F4F)   // nf-md-focus_field — a camera-style focus frame: one centred window
var tilingFair      = _c(0xF05D1)   // nf-md-scale_balance — a balance scale for "fair" (even) distribution
var tilingFloating  = _c(0xF05B2)   // nf-md-window_restore — an overlapping-windows pictogram

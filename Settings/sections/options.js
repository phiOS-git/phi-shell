.pragma library

// phiOS — Settings/options.js (Out-of-plan: settings-overhaul, batch A).
//
// The searchable catalogue of every settings OPTION, one level below
// Settings/sections.json (which lists the nine SECTIONS). The user's
// directive for this round: the search must not filter options out, it
// must HIGHLIGHT matches; Enter selects the top-ranked result; a result
// can be a whole section or one specific option; and picking an option
// must select its section, scroll the panel to that option, and pulse it.
// System overlays reach the same path — `qs ipc call settings reveal
// <id>` — to jump straight to a control.
//
// ID scheme: "<sectionType>.<rest>", dotted. The part before the first "."
// is always a Settings/sections.json `type`, so the reveal path derives
// the section from the id with no extra lookup (Services/SettingsPanel.qml
// reveal()). A bare section type ("theme") is a section-level entry.
//
// Keeping this list in sync with the SettingsRow `optionId`s each section
// declares is a discipline, the same one Settings/sections.json already
// asks for: a SettingsRow whose id is absent here logs a warning at
// registration (Settings/SettingsRow.qml), so a drift shows up in the
// screenshot pass rather than silently.

// section: true  → a whole section, ranked alongside options so Enter can
//                  land on either. Titles/keywords mirror sections.json.
var SECTIONS = [
    { id: "general",       title: "General",       keywords: "machine hardware hostname cpu gpu ram memory disk storage os kernel uptime model" },
    { id: "theme",         title: "Theme",         keywords: "appearance colour color palette accent font typography size scale spacing radius border variant dark light animation motion easing bezier wallpaper texture night shift true tone cursor spotlight lock screen effect lava lamp matrix starfield" },
    { id: "connectivity",  title: "Connectivity",  keywords: "network tailscale vpn wireguard wifi wi-fi ssid bluetooth speed ping download upload latency overlay" },
    { id: "devices",       title: "Devices",       keywords: "audio volume mute output input sink source microphone monitor display resolution scaling chroma keyboard backlight per-key rgb mouse trackpad pointer sensitivity brightness" },
    { id: "keybindings",   title: "Keybindings",   keywords: "shortcuts binds hotkeys hyprland keys reference cheatsheet context" },
    { id: "notifications", title: "Notifications", keywords: "do not disturb dnd rules per app toast sound chroma blink priority" },
    { id: "security",      title: "Security",      keywords: "clamav antivirus scan quarantine signatures face unlock howdy secrets keepass vault" },
    { id: "aiAgent",       title: "AI Agent",      keywords: "phi agent activation project personality broker opencode model provider key egress whitelist systemd units memory proposals" },
    { id: "updates",       title: "Updates",       keywords: "packages system state version pacman aur npm flatpak appimage phi-packages check upgrade" }
];

// One row per control the panel exposes. `title` is what the user reads on
// the row; `keywords` widen the match. Ordered by section, roughly by
// on-screen order.
var OPTIONS = [
    // --- General -------------------------------------------------------
    { id: "general.machine",  title: "Machine",       keywords: "hostname cpu processor gpu graphics ram memory model hardware" },
    { id: "general.system",   title: "System",        keywords: "os kernel uptime arch linux version disk storage free root filesystem" },
    { id: "general.battery",  title: "Battery",       keywords: "charge health cycles time remaining power profile tlp saver" },

    // --- Theme --------------------------------------------------------
    { id: "theme.variant",            title: "Light / dark variant",   keywords: "appearance theme dark light mode" },
    { id: "theme.colors.accent",      title: "Accent colour",          keywords: "palette highlight detail focus ring" },
    { id: "theme.colors.check",       title: "phi theme check",        keywords: "contrast wcag accessibility ratio pass fail" },
    { id: "theme.colors.bg-0",        title: "Background (main)",       keywords: "palette surface colour" },
    { id: "theme.colors.bg-1",        title: "Surface +1",             keywords: "palette colour" },
    { id: "theme.colors.bg-2",        title: "Surface +2",             keywords: "palette colour" },
    { id: "theme.colors.bg-3",        title: "Surface +3",             keywords: "palette colour" },
    { id: "theme.colors.fg-0",        title: "Text (primary)",         keywords: "palette foreground colour ink" },
    { id: "theme.colors.fg-1",        title: "Text, secondary",        keywords: "palette foreground colour" },
    { id: "theme.colors.fg-2",        title: "Text, muted",            keywords: "palette foreground colour" },
    { id: "theme.colors.fg-3",        title: "Text, faint",            keywords: "palette foreground colour" },
    { id: "theme.colors.border",      title: "Border",                 keywords: "palette line hairline colour" },
    { id: "theme.colors.border-strong", title: "Border, strong",       keywords: "palette outline colour" },
    { id: "theme.colors.error",       title: "Error colour",           keywords: "palette semantic red danger" },
    { id: "theme.colors.warn",        title: "Warning colour",         keywords: "palette semantic amber yellow" },
    { id: "theme.colors.success",     title: "Success colour",         keywords: "palette semantic green" },
    { id: "theme.colors.info",        title: "Info colour",            keywords: "palette semantic blue" },
    { id: "theme.fonts.mono",         title: "Mono font",              keywords: "typography family terminal code" },
    { id: "theme.fonts.reading",     title: "Reading font",           keywords: "typography family serif prose" },
    { id: "theme.fonts.ui",           title: "UI font",                keywords: "typography family sans interface" },
    { id: "theme.shape.font-scale",   title: "Font scale",             keywords: "typography size multiplier bigger smaller" },
    { id: "theme.shape.space-scale",  title: "Spacing scale",          keywords: "rhythm density gap multiplier" },
    { id: "theme.shape.radius-base",  title: "Radius, base",           keywords: "corner rounding shape" },
    { id: "theme.shape.radius-small", title: "Radius, small",          keywords: "corner rounding shape isle" },
    { id: "theme.shape.radius-large", title: "Radius, large",          keywords: "corner rounding shape runner" },
    { id: "theme.animations",         title: "Animations",             keywords: "motion transition duration easing bezier curve editor" },
    { id: "theme.wallpaper.color",    title: "Wallpaper solid colour", keywords: "background base fill" },
    { id: "theme.wallpaper.image",    title: "Wallpaper image",        keywords: "background picture photo folder pick add" },
    { id: "theme.wallpaper.mode",     title: "Wallpaper mode",         keywords: "background fit cover contain stretch repeat fill" },
    { id: "theme.wallpaper.scale",    title: "Wallpaper scale",        keywords: "background zoom size" },
    { id: "theme.wallpaper.texture",  title: "Wallpaper texture",      keywords: "background grain leather rock noise paper overlay intensity" },
    { id: "theme.nightshift",         title: "Night shift",            keywords: "warm temperature evening true tone ambient light" },
    { id: "theme.spotlight",          title: "Cursor spotlight",       keywords: "vignette pointer glow" },
    { id: "theme.lockscreen",         title: "Lock screen effect",     keywords: "ambient backdrop lava lamp matrix rain starfield none" },

    // --- Connectivity -----------------------------------------------
    { id: "connectivity.bluetooth",   title: "Bluetooth",              keywords: "adapter device pair connect disconnect" },
    { id: "connectivity.wifi",        title: "Wi-Fi",                  keywords: "wireless ssid signal network manage" },
    { id: "connectivity.wifi.speed",  title: "Wi-Fi speed & ping",     keywords: "throughput download upload latency graph chart flow bandwidth" },
    { id: "connectivity.vpn",         title: "VPN (WireGuard)",        keywords: "wireguard tunnel wg-quick up down" },
    { id: "connectivity.tailscale",   title: "Tailscale",              keywords: "overlay mesh tailnet hostname up down" },

    // --- Devices ---------------------------------------------------
    { id: "devices.audio.output",     title: "Audio output",           keywords: "sink speaker headphones device select volume" },
    { id: "devices.audio.input",      title: "Audio input",            keywords: "source microphone mic device select" },
    { id: "devices.monitors",         title: "Monitors",               keywords: "display resolution scale refresh layout" },
    { id: "devices.pointer",          title: "Pointer",                keywords: "mouse trackpad sensitivity acceleration" },
    { id: "devices.chroma",           title: "Chroma keyboard",        keywords: "razer rgb lighting backlight on off" },
    { id: "devices.chroma.color",     title: "Chroma static colour",   keywords: "razer rgb solid" },
    { id: "devices.chroma.advanced",  title: "Chroma per-key colours", keywords: "razer rgb advanced individual keycap override map" },
    { id: "devices.chroma.integrations", title: "Chroma integrations", keywords: "razer battery notifications neovim power key blink mode" },

    // --- Keybindings --------------------------------------------
    { id: "keybindings.reference",     title: "Keybinding reference",   keywords: "shortcuts binds hyprctl grouped context" },

    // --- Notifications ---------------------------------------
    { id: "notifications.dnd",         title: "Do not disturb",         keywords: "dnd silence duration" },
    { id: "notifications.rules",       title: "Per-app rules",          keywords: "application mute no toast no sound priority" },
    { id: "notifications.sound",       title: "Sound & testing",        keywords: "audio beep chime pw-play freedesktop volume test notification" },
    { id: "notifications.retention",   title: "History retention",      keywords: "keep days auto clear prune old clean all" },
    { id: "notifications.chroma",      title: "Keyboard blink on notification", keywords: "chroma razer function row" },

    // --- Updates --------------------------------------------
    { id: "updates.system",           title: "System state",           keywords: "version phios phi phi-packages" },
    { id: "updates.packages",         title: "Packages",               keywords: "pacman aur npm flatpak appimage phi list manager" }
];

function _all() { return SECTIONS.concat(OPTIONS); }

// Is this id present in the catalogue (section or option)?
function known(id) {
    var all = _all();
    for (var i = 0; i < all.length; i++) if (all[i].id === id) return true;
    return false;
}

// Section type for any id: the substring before the first ".", or the id
// itself for a section-level entry.
function sectionOf(id) {
    var i = id.indexOf(".");
    return i === -1 ? id : id.substring(0, i);
}

function isSection(id) { return id.indexOf(".") === -1; }

// 0 = no match. Higher = better. Title beats keywords; a prefix beats a
// mid-string hit; a section-level entry is nudged below an option of the
// same strength so "search accent → Enter" lands on the option, not the
// whole Theme section.
function score(entry, query) {
    var q = String(query || "").toLowerCase().trim();
    if (q.length === 0) return 0;
    var t = String(entry.title || "").toLowerCase();
    var k = " " + String(entry.keywords || "").toLowerCase() + " ";
    var s = 0;
    if (t === q) s = 100;
    else if (t.indexOf(q) === 0) s = 80;
    else if (t.indexOf(q) !== -1) s = 60;
    else if (k.indexOf(" " + q) !== -1) s = 40;
    else if (k.indexOf(q) !== -1) s = 20;
    if (s > 0 && entry.section) s -= 5;
    return s;
}

// Does this specific option id match the query at all?
function matches(id, query) {
    var all = _all();
    for (var i = 0; i < all.length; i++) {
        if (all[i].id === id) return score(all[i], query) > 0;
    }
    return false;
}

// Does any option (or the section entry itself) under this section type
// match — used to highlight a nav entry without hiding it.
function sectionMatches(sectionType, query) {
    var all = _all();
    for (var i = 0; i < all.length; i++) {
        if (sectionOf(all[i].id) === sectionType && score(all[i], query) > 0) return true;
    }
    return false;
}

// Every {id, score} that matches, best first.
function rank(query) {
    var all = _all();
    var hits = [];
    for (var i = 0; i < all.length; i++) {
        var sc = score(all[i], query);
        if (sc > 0) hits.push({ id: all[i].id, title: all[i].title, section: !!all[i].section, score: sc });
    }
    hits.sort(function (a, b) { return b.score - a.score; });
    return hits;
}

// The id Enter should act on, or "" when nothing matches.
function topResult(query) {
    var r = rank(query);
    return r.length > 0 ? r[0].id : "";
}

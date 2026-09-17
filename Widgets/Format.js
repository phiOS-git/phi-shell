.pragma library

// Plain formatting helpers shared by every status-bar overlay and corner
// panel that shows a live rate, countdown or elapsed time — no QML
// dependency, so this is a pure-function .js like Bar/glyphs.js and
// Launcher/prefixes.js, not a component.

function rate(kbps) {
    if (kbps >= 1000) return (kbps / 1000).toFixed(1) + " Mb/s"
    return Math.round(kbps) + " kb/s"
}

function countdown(targetMs, nowMs) {
    const totalSeconds = Math.max(0, Math.ceil((targetMs - nowMs) / 1000))
    const h = Math.floor(totalSeconds / 3600)
    const m = Math.floor((totalSeconds % 3600) / 60)
    const s = totalSeconds % 60
    if (h > 0) return h + "h " + m + "m"
    return m + ":" + (s < 10 ? "0" : "") + s
}

function stopwatch(ms) {
    const totalSeconds = Math.floor(ms / 1000)
    const h = Math.floor(totalSeconds / 3600)
    const m = Math.floor((totalSeconds % 3600) / 60)
    const s = totalSeconds % 60
    if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    return m + ":" + (s < 10 ? "0" : "") + s
}

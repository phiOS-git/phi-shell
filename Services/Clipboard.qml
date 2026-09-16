pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config

// phiOS — Services/Clipboard (S-32, ADR 073: the shell implements clipboard
// history itself; master plan §8.3 surface 5). Captured by a single
// `wl-paste --watch` Process, matching cliphist's own established
// integration shape (`wl-paste --watch cliphist store`, the tool this step
// removes per C-07) but writing directly to $XDG_STATE_HOME/phi/clipboard
// instead — that directory is the storage shape S-13 deferred to whichever
// step first needed a clipboard collection (this one), same as S-30 defined
// one for notification history.
//
// No manifest file: the capture script is plain POSIX sh (no JSON writer
// available there), so the filesystem itself is the structure — one
// <id>.data + <id>.mime pair per entry under clipboardEntriesDir, `id` is
// `date +%s%N` (nanoseconds since epoch, so lexicographic and numeric sort
// agree and double as the timestamp), and a single `latest` file holds the
// newest id purely so one watched FileView can signal "something new
// arrived" without a polling timer (FileView.watchChanges, confirmed
// against io/fileview.hpp to fire on an external process's write, not only
// on this file's own setText/setData). pins.json is the one piece of
// structure Quickshell itself owns — pinning is a UI action, not a
// capture-time decision, so it is the one place JSON is actually
// convenient to write.
//
// Sensitive exclusion happens INSIDE the capture script, before anything
// ever touches disk: `wl-paste --list-types` is checked for
// `x-kde-passwordManagerHint` (master plan §9.13's own note — KeePassXC
// already sets it) and the entry is dropped, never written, never visible
// to Quickshell at all. This is a cross-dependency on the M6 secrets
// decision (KeePassXC vs. Vaultwarden) already flagged in S-32's own PROGRESS
// row: if the eventual choice does not set this MIME hint, this exclusion
// silently stops working and needs reimplementing against whatever the
// chosen manager does instead.
//
// File support (text/uri-list) is explicitly NOT built here (S-32 AGENT:
// "not required now") — the two-file-per-entry shape (data + a recorded
// mime type) already accommodates it later without restructuring: a
// text/uri-list entry is just another mime value, the same as image/png.

Singleton {
    id: root

    // "TTL: minimo un mese; valore esatto rimandato al consumo reale"
    // (master plan §5, S-32 AGENT). 30 is this step's own placeholder for
    // "one month", not a value any document fixes precisely.
    readonly property int ttlDays: 30

    property var entries: []  // [{id, mime, timestamp, preview}], newest first, rebuilt from disk on refresh()
    property var pinnedIds: [] // array of id strings, persisted to pins.json

    // docs/TODO.md: "there is not way to set rules for what should not be
    // saved in the clipboard history." The capture script (`watcher`
    // below) already excludes one thing before it ever touches disk —
    // KeePassXC's password-manager MIME hint — but that mechanism is a
    // single hardcoded shell case, not something a user can add to.
    // Re-templating and restarting the long-lived `wl-paste --watch`
    // process for a live rule change is real complexity for what a plain
    // QML-side check achieves just as well for the one thing this project
    // can actually see rules against (mime type, captured text content):
    // checked once, the instant an entry is first observed as new (see
    // listProcess's own onStreamFinished below) — a match is deleted
    // immediately via the same deleteEntry() a manual delete uses, so it
    // never even flashes into the visible list, and never retroactively
    // touches anything captured before the rule existed.
    property bool excludeImages: false
    property var excludeRules: [] // lowercase substrings matched against preview text

    function setExcludeImages(b) {
        root.excludeImages = !!b
        root._persistRules()
    }

    function addExcludeRule(pattern) {
        const p = String(pattern || "").trim().toLowerCase()
        if (p.length === 0 || root.excludeRules.indexOf(p) !== -1) return
        root.excludeRules = root.excludeRules.concat([p])
        root._persistRules()
    }

    function removeExcludeRule(pattern) {
        root.excludeRules = root.excludeRules.filter((p) => p !== pattern)
        root._persistRules()
    }

    function _matchesExcludeRule(entry) {
        if (root.excludeImages && entry.mime === "image/png") return true
        const text = (entry.preview || "").toLowerCase()
        for (let i = 0; i < root.excludeRules.length; i++)
            if (text.indexOf(root.excludeRules[i]) !== -1) return true
        return false
    }

    // docs/TODO.md: "add the clipboard icon to the status bar (with
    // animation for when an element is added)". Bar/modules/Clipboard.qml
    // is the one consumer. Deliberately NOT fired on every refresh():
    // refresh() also runs on shell startup (ensureDirs.onExited) and every
    // time Panels/tabs/Clipboard.qml's own tab becomes visible — neither
    // is a new clipboard capture, and firing on those would flash the bar
    // icon for no reason. Fired only from listProcess's own onExited
    // below, and only when the new top-of-list id was not already
    // anywhere in the previous entries list (see there for why "not
    // already present" and not just "differs from the old top" — a
    // deletion promoting an existing entry to position 0 must not count).
    signal arrived(var entry)
    property bool _everLoaded: false

    function isPinned(id) {
        return root.pinnedIds.indexOf(id) !== -1
    }

    function pin(id) {
        if (root.isPinned(id)) return
        root.pinnedIds = root.pinnedIds.concat([id])
        _persistPins()
    }

    function unpin(id) {
        root.pinnedIds = root.pinnedIds.filter((x) => x !== id)
        _persistPins()
    }

    function contentPath(id) {
        return Config.Paths.clipboardEntriesDir + "/" + id + ".data"
    }

    // Copies a historical entry back onto the live clipboard — the reason
    // a clipboard *history* is useful at all, not spelled out step by step
    // in the card but the evident point of the feature.
    function restore(id, mime) {
        restoreComponent.createObject(root, { entryId: id, mime: mime })
    }

    // Every one-shot Process in this file — this block and listProcess/
    // mimeReaderComponent below — sets running: false in its own onExited
    // before anything else. Read from the real Quickshell source
    // (io/process.cpp) rather than assumed: Process.onFinished() calls
    // startProcessIfReady() as its LAST step, after the exited signal (this
    // file's onExited handlers) has already run synchronously — so if
    // `running` were left true, a one-shot command would silently respawn
    // itself forever the moment it first exits ("running = false; running =
    // true" is literally that file's own comment for how a deliberate
    // restart is meant to be requested, which is exactly the trap here if
    // left unset). `watcher` below is the one Process in this file that is
    // MEANT to auto-restart this way if `wl-paste --watch` ever exits
    // unexpectedly, so it alone never resets `running`.
    //
    // Every dynamically created Process also destroys itself by its own
    // explicit id, never `this`/`parent`: Process is not confirmed to be an
    // Item (whose `parent` is a declared QML property with defined
    // behaviour) rather than a plain QtObject (where a bare `parent` is not
    // guaranteed to be a usable QML property at all) — self-id is the one
    // reference this file does not have to guess about.
    property Component restoreComponent: Component {
        Process {
            id: restoreProc
            property string entryId: ""
            property string mime: "text/plain"
            command: ["sh", "-c",
                'wl-copy --type "$1" < "$2"',
                "restore", mime, root.contentPath(entryId)]
            running: true
            onExited: {
                restoreProc.running = false
                restoreProc.destroy()
            }
        }
    }

    function deleteEntry(id) {
        root.unpin(id)
        rmComponent.createObject(root, { entryId: id })
    }

    // rework-status-bar.md Features item 3: "add an option to clear
    // clipboard history (does not delete pinned options)."
    function clearHistory() {
        const ids = root.entries.filter((e) => !root.isPinned(e.id)).map((e) => e.id)
        for (let i = 0; i < ids.length; i++) root.deleteEntry(ids[i])
    }

    property Component rmComponent: Component {
        Process {
            id: rmProc
            property string entryId: ""
            command: ["rm", "-f", root.contentPath(entryId),
                Config.Paths.clipboardEntriesDir + "/" + entryId + ".mime"]
            running: true
            onExited: {
                rmProc.running = false
                rmProc.destroy()
                root.refresh()
            }
        }
    }

    function refresh() {
        listProcess.running = true
    }

    Process {
        id: ensureDirs
        command: ["mkdir", "-p", Config.Paths.clipboardEntriesDir]
        running: true
        onExited: {
            ensureDirs.running = false
            root.refresh()
        }
    }

    // The capture process. Runs once for the shell's whole lifetime;
    // wl-paste re-invokes the inner `sh -c` script fresh for every
    // clipboard change (the same mechanism cliphist's own integration
    // relies on), so this single long-lived Process is enough.
    Process {
        id: watcher
        command: ["wl-paste", "--watch", "sh", "-c", `
dir="${'$'}{XDG_STATE_HOME:-${'$'}HOME/.local/state}/phi/clipboard"
mkdir -p "$dir/entries"
types=$(wl-paste --list-types 2>/dev/null)
case "$types" in
  *x-kde-passwordManagerHint*) cat >/dev/null; exit 0 ;;
esac
id=$(date +%s%N)
if printf '%s\\n' "$types" | grep -qx "image/png"; then
  cat >/dev/null
  wl-paste --type image/png > "$dir/entries/$id.data" 2>/dev/null
  printf '%s' "image/png" > "$dir/entries/$id.mime"
else
  cat > "$dir/entries/$id.data"
  printf '%s' "text/plain" > "$dir/entries/$id.mime"
fi
printf '%s' "$id" > "$dir/latest"
`.trim()]
        running: true
    }

    FileView {
        id: latestFile
        path: Config.Paths.clipboardLatestFile
        watchChanges: true
        onLoaded: root.refresh()
        onFileChanged: root.reload()
        onLoadFailed: (error) => {
            // FileNotFound before the first clipboard change since install
            // is expected: entries starts empty.
        }
    }
    function reload() { latestFile.reload() }

    // OOP-06: one shell loop reads every entry's mime AND a preview snippet
    // in a single pass, emitting `id<TAB>mime<TAB>preview` — so `entries`
    // carries a `preview` string the clipboard panel can filter and render
    // synchronously, with no per-entry FileView. Replaces the earlier
    // "list ids, then spawn one mime-reader Process per id" shape.
    //
    // The snippet is the first 200 BYTES of the file (`head -c`), not the
    // first LINE (`head -n1 | cut -c1-200`, the original shape). Two
    // problems with the line-based version, either of which explains
    // docs/TODO.md's "the clipboard shows '(empty)' when the content is
    // too long": (1) `head -n1` returns an EMPTY string whenever the
    // file's first physical line is blank — common for anything copied
    // with a leading newline (a browser selection, an editor block) — no
    // matter how much real content follows; (2) `cut -c` has to buffer an
    // *entire line* before it can emit anything, so a long paste with no
    // embedded newline at all (one big unbroken line) made `cut` buffer
    // the whole multi-megabyte line before producing 200 chars of it —
    // measured directly (this part needs no Hyprland/Quickshell, it's
    // plain shell) at ~1.9s for a 50MB single line vs. ~10ms for the
    // `head -c` version below, confirming the cost scales with content
    // size, though not confirming it ever actually reached zero output.
    // `head -c` fixes both: it never depends on line structure and reads
    // exactly 200 bytes regardless of size. Embedded newlines/tabs/NULs
    // are folded to spaces (not stripped) so a multi-line snippet still
    // reads as one TSV row.
    Process {
        id: listProcess
        command: ["sh", "-c", `
dir="$1"
for m in "$dir"/*.mime; do
  [ -e "$m" ] || continue
  id=$(basename "$m" .mime)
  mime=$(cat "$m" 2>/dev/null)
  first=$(head -c 200 "$dir/$id.data" 2>/dev/null | tr '\\n\\r\\t\\000' '    ')
  printf '%s\\t%s\\t%s\\n' "$id" "$mime" "$first"
done
`.trim(), "list", Config.Paths.clipboardEntriesDir]
        onExited: listProcess.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").filter((s) => s.length > 0)
                const next = lines.map((ln) => {
                    const parts = ln.split("\t")
                    const id = parts[0]
                    return {
                        id: id,
                        timestamp: Math.round(parseInt(id, 10) / 1e6),
                        mime: parts[1] && parts[1].length > 0 ? parts[1] : "text/plain",
                        preview: parts.length > 2 ? parts[2] : "",
                    }
                }).filter((e) => e.id && e.id.length > 0)
                next.sort((a, b) => b.timestamp - a.timestamp)

                // Exclusion rules — only against entries genuinely new
                // THIS pass (never retroactive to what a rule's own
                // `_everLoaded` guard already protects, see that
                // property's own comment above and _matchesExcludeRule's).
                // A match is deleted immediately and dropped from `next`
                // before it is ever assigned to root.entries, so it never
                // flashes into the visible list for even one frame.
                let filtered = next
                if (root._everLoaded) {
                    const prevIdSet = root.entries.map((e) => e.id)
                    const toDelete = []
                    filtered = next.filter((e) => {
                        if (prevIdSet.indexOf(e.id) !== -1) return true
                        if (root._matchesExcludeRule(e)) { toDelete.push(e.id); return false }
                        return true
                    })
                    for (let i = 0; i < toDelete.length; i++) root.deleteEntry(toDelete[i])
                }

                // rework-status-bar.md Features item 1: "the clipboard
                // history should automatically filter out 'empty' values."
                // Applied on every pass (not gated by `_everLoaded` the way
                // the exclusion rules above deliberately are — those are a
                // user-authored rule that should only ever act going
                // forward; "no empty entries" is a standing invariant, the
                // same kind of ongoing housekeeping `_sweepExpired` below
                // already does), so a stray empty entry from before this
                // existed gets cleaned up too, not just future ones. An
                // image is never "empty" in this sense — `preview` (this
                // file's only synchronously-available content signal, see
                // this file's own header) is the one thing to check, and
                // only for text. A pinned entry is protected, the same
                // "pins survive automatic deletion" rule `_sweepExpired`
                // already follows.
                const emptyIds = filtered
                    .filter((e) => e.mime !== "image/png" && e.preview.trim().length === 0 && !root.isPinned(e.id))
                    .map((e) => e.id)
                if (emptyIds.length > 0) {
                    filtered = filtered.filter((e) => emptyIds.indexOf(e.id) === -1)
                    for (let i = 0; i < emptyIds.length; i++) root.deleteEntry(emptyIds[i])
                }

                // rework-status-bar.md Features item 2: "the clipboard
                // history should check for duplicate entries, if any is
                // found the details are changed, it gets pushed as first
                // element, but there must not be entries with the same
                // value." Grouped by `preview` (same content-signal
                // limitation as above — this file has no cheaper way to
                // compare full content synchronously across every entry).
                // An id IS a capture time, not a field that can be renamed
                // in place, so "the details are changed, pushed as first"
                // is realised by keeping the NEWEST capture in each
                // duplicate group (already at/near the front of this
                // already-newest-first list) and deleting every older
                // duplicate outright — not just hiding it, so it stops
                // occupying a real TTL slot on disk. Whichever member of a
                // group is pinned is kept instead, protecting the pin the
                // same way `_sweepExpired` already does; images are exempt
                // (two different screenshots can share the same 200-byte
                // preview snippet with genuinely different full content).
                const byValue = {}
                for (let i = 0; i < filtered.length; i++) {
                    const e = filtered[i]
                    if (e.mime === "image/png" || e.preview.length === 0) continue
                    if (!byValue[e.preview]) byValue[e.preview] = []
                    byValue[e.preview].push(e)
                }
                const dupIds = []
                for (const key in byValue) {
                    const group = byValue[key]
                    if (group.length < 2) continue
                    let keep = group[0]
                    for (let i = 1; i < group.length; i++) {
                        const cand = group[i]
                        const candPinned = root.isPinned(cand.id)
                        const keepPinned = root.isPinned(keep.id)
                        if (candPinned && !keepPinned) keep = cand
                        else if (candPinned === keepPinned && cand.timestamp > keep.timestamp) keep = cand
                    }
                    for (let i = 0; i < group.length; i++)
                        if (group[i].id !== keep.id) dupIds.push(group[i].id)
                }
                if (dupIds.length > 0) {
                    filtered = filtered.filter((e) => dupIds.indexOf(e.id) === -1)
                    for (let i = 0; i < dupIds.length; i++) root.deleteEntry(dupIds[i])
                }

                // "not already present anywhere in the old list", not
                // "differs from the old top" — see the `arrived` signal's
                // own comment above for why: a deletion can promote an
                // existing entry to position 0 without anything new
                // having been captured, and that must not fire this.
                if (root._everLoaded && filtered.length > 0) {
                    const prevIds = root.entries.map((e) => e.id)
                    if (prevIds.indexOf(filtered[0].id) === -1) root.arrived(filtered[0])
                }
                root._everLoaded = true

                root.entries = filtered
            }
        }
    }

    function _persistPins() {
        pinsFile.setText(JSON.stringify(root.pinnedIds))
    }

    FileView {
        id: pinsFile
        path: Config.Paths.clipboardPinsFile
        onLoaded: {
            try {
                const parsed = JSON.parse(pinsFile.text())
                if (Array.isArray(parsed)) root.pinnedIds = parsed
            } catch (e) {
                console.warn("phi-shell: clipboard pins.json failed to parse: " + e)
            }
        }
        onLoadFailed: (error) => {
            // FileNotFound on first run is expected: nothing pinned yet.
        }
    }

    function _persistRules() {
        rulesFile.setText(JSON.stringify({
            excludeImages: root.excludeImages,
            excludeRules: root.excludeRules
        }, null, 2))
    }

    FileView {
        id: rulesFile
        path: Config.Paths.clipboardRulesFile
        onLoaded: {
            try {
                const parsed = JSON.parse(rulesFile.text())
                if (parsed && typeof parsed === "object") {
                    if (typeof parsed.excludeImages === "boolean") root.excludeImages = parsed.excludeImages
                    if (Array.isArray(parsed.excludeRules)) root.excludeRules = parsed.excludeRules
                }
            } catch (e) {
                console.warn("phi-shell: clipboard rules.json failed to parse: " + e)
            }
        }
        onLoadFailed: (error) => {
            // FileNotFound on first run is expected: no rules yet.
        }
    }

    // TTL sweep (§5's "minimo un mese"): runs once shortly after startup
    // and every six hours after that — frequent enough that an entry never
    // outlives ttlDays by more than that margin, infrequent enough it is
    // not meaningful background load.
    Timer {
        interval: 6 * 60 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root._sweepExpired()
    }

    function _sweepExpired() {
        const cutoff = Date.now() - root.ttlDays * 24 * 60 * 60 * 1000
        for (let i = 0; i < root.entries.length; i++) {
            const e = root.entries[i]
            if (e.timestamp < cutoff && !root.isPinned(e.id)) root.deleteEntry(e.id)
        }
    }
}

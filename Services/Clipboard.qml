pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config

// The shell implements clipboard history itself. Captured by a single
// long-lived `wl-paste --watch` Process, writing directly to
// $XDG_STATE_HOME/phi/clipboard.
//
// No manifest file: the capture script is plain POSIX sh (no JSON writer
// available there), so the filesystem itself is the structure — one
// <id>.data + <id>.mime pair per entry under clipboardEntriesDir, `id` is
// `date +%s%N` (nanoseconds since epoch, so lexicographic and numeric sort
// agree and double as the timestamp), and a single `latest` file holds the
// newest id so one watched FileView can signal "something new arrived"
// without a polling timer. pins.json is the one piece of structure
// Quickshell itself owns — pinning is a UI action, not a capture-time
// decision.
//
// Sensitive exclusion happens INSIDE the capture script, before anything
// ever touches disk: `wl-paste --list-types` is checked for
// `x-kde-passwordManagerHint` (KeePassXC sets it) and the entry is
// dropped, never written, never visible to Quickshell. If the eventual
// password-manager choice doesn't set this MIME hint, this exclusion
// silently stops working and needs reimplementing against whatever it
// does instead.
//
// File support (text/uri-list) is not built — the two-file-per-entry
// shape (data + a recorded mime type) already accommodates it later
// without restructuring: it's just another mime value, same as image/png.

Singleton {
    id: root

    // 30 days — a placeholder for "about a month", not a value fixed
    // precisely anywhere.
    readonly property int ttlDays: 30

    property var entries: []  // [{id, mime, timestamp, preview}], newest first, rebuilt from disk on refresh()
    property var pinnedIds: [] // array of id strings, persisted to pins.json

    // Per-user rules for what should never be saved. The capture script
    // already excludes one thing before it ever touches disk (KeePassXC's
    // MIME hint), but that's a single hardcoded case, not user-editable.
    // Re-templating and restarting the long-lived `wl-paste --watch`
    // process for a live rule change is real complexity a plain QML-side
    // check avoids: checked once, the instant an entry is first observed
    // as new (see listProcess's onStreamFinished below), a match is
    // deleted immediately via the same deleteEntry() a manual delete
    // uses, so it never flashes into the visible list and never
    // retroactively touches anything captured before the rule existed.
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

    // Fired only from listProcess's onExited below, and only when the new
    // top-of-list id was not already anywhere in the previous entries list
    // — not just "differs from the old top", since a deletion promoting an
    // existing entry to position 0 must not count as an arrival.
    // Deliberately not fired on every refresh(): refresh() also runs on
    // shell startup and whenever the clipboard tab becomes visible,
    // neither of which is a new capture.
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

    // Copies a historical entry back onto the live clipboard.
    function restore(id, mime) {
        restoreComponent.createObject(root, { entryId: id, mime: mime })
    }

    // Every one-shot Process in this file sets running: false in its own
    // onExited before anything else: Process.onFinished() restarts
    // automatically if `running` is still true when it exits, so without
    // this a one-shot command would respawn itself forever the moment it
    // first exits. `watcher` below is the one Process meant to
    // auto-restart this way if `wl-paste --watch` ever exits
    // unexpectedly, so it alone never resets `running`.
    //
    // Every dynamically created Process also destroys itself by its own
    // explicit id, never `this`/`parent` — Process is not confirmed to be
    // an Item, so a bare `parent` reference isn't guaranteed usable.
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

    // Clears history but keeps pinned entries.
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
    // clipboard change, so this single long-lived Process is enough.
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

    // One shell loop reads every entry's mime AND a preview snippet in a
    // single pass, emitting `id<TAB>mime<TAB>preview` — so `entries`
    // carries a `preview` string the clipboard panel can filter and
    // render synchronously, with no per-entry FileView.
    //
    // The snippet is the first 200 BYTES of the file (`head -c`), not the
    // first LINE: a line-based read returns empty for anything copied
    // with a leading newline (a browser selection, an editor block)
    // regardless of how much content follows, and for one huge unbroken
    // line it has to buffer the entire line before producing any output —
    // measured at ~1.9s for a 50MB single line vs. ~10ms with `head -c`.
    // `head -c` never depends on line structure. Embedded newlines/tabs/
    // NULs are folded to spaces (not stripped) so a multi-line snippet
    // still reads as one TSV row.
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

                // Exclusion rules apply only to entries genuinely new this
                // pass (guarded by _everLoaded, never retroactive). A
                // match is deleted immediately and dropped from `next`
                // before it's ever assigned to root.entries, so it never
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

                // Empty entries are filtered out on every pass, not gated
                // by _everLoaded the way exclusion rules are — "no empty
                // entries" is a standing invariant, not a rule that should
                // only act going forward, so a stray empty entry from
                // before this existed gets cleaned up too. `preview` (the
                // only synchronously-available content signal) is checked
                // only for text — an image is never "empty" in this
                // sense. Pinned entries are protected.
                const emptyIds = filtered
                    .filter((e) => e.mime !== "image/png" && e.preview.trim().length === 0 && !root.isPinned(e.id))
                    .map((e) => e.id)
                if (emptyIds.length > 0) {
                    filtered = filtered.filter((e) => emptyIds.indexOf(e.id) === -1)
                    for (let i = 0; i < emptyIds.length; i++) root.deleteEntry(emptyIds[i])
                }

                // Duplicate entries (same `preview` — the only cheap
                // full-content proxy available) are collapsed: the newest
                // capture in each group is kept, every older duplicate is
                // deleted outright so it stops occupying a TTL slot on
                // disk. A pinned member of a group is kept instead.
                // Images are exempt — two different screenshots can share
                // the same 200-byte preview with genuinely different
                // content.
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

                // "Not already present anywhere in the old list", not
                // "differs from the old top" — see the `arrived` signal's
                // own comment above.
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

    // Runs once shortly after startup and every six hours after that —
    // frequent enough an entry never outlives ttlDays by more than that
    // margin, infrequent enough it's not meaningful background load.
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

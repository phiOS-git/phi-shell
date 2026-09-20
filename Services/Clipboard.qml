pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config


Singleton {
    id: root

    // 30 days — a placeholder for "about a month".
    readonly property int ttlDays: 30

    property var entries: []  // [{id, mime, timestamp, preview}], newest first
    property var pinnedIds: [] // array of id strings, persisted to pins.json

    // Per-user rules: checked once on first observation, deleted immediately
    // via deleteEntry(), so never visible and never retroactive.
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

    // Fires only when new top-of-list not already in previous entries (not just
    // different from old top). Not on every refresh() (startup/tab visible).
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

    // One-shot Process: set running=false in onExited or it auto-restarts.
    // watcher alone auto-restarts. Dynamic Process: destroy via explicit id.
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

    // Capture process (shell lifetime). wl-paste re-invokes script per change.
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
            // FileNotFound before first clipboard change is expected.
        }
    }
    function reload() { latestFile.reload() }

    // One shell loop reads mime + preview snippet, emitting id<TAB>mime<TAB>preview.
    // Snippet: first 200 BYTES (head -c, not line-based; handles leading newlines).
    // Newlines/tabs/NULs folded to spaces (multi-line as one TSV row).
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

                // Exclusion rules apply only to genuinely new entries. Deleted
                // immediately, never visible.
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

                // Empty entries filtered every pass (standing invariant).
                // preview checked only for text, images exempt. Pinned protected.
                const emptyIds = filtered
                    .filter((e) => e.mime !== "image/png" && e.preview.trim().length === 0 && !root.isPinned(e.id))
                    .map((e) => e.id)
                if (emptyIds.length > 0) {
                    filtered = filtered.filter((e) => emptyIds.indexOf(e.id) === -1)
                    for (let i = 0; i < emptyIds.length; i++) root.deleteEntry(emptyIds[i])
                }

                // Duplicates collapsed: newest kept, older deleted. Pinned member
                // kept instead. Images exempt.
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

                // "Not already present anywhere in the old list", not "differs
                // from the old top" — the `arrived` signal's own comment.
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

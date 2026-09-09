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

    // OOP-06: one shell loop reads every entry's mime AND its first line in
    // a single pass, emitting `id<TAB>mime<TAB>firstline` — so `entries`
    // carries a `preview` string the clipboard panel can filter and render
    // synchronously, with no per-entry FileView. Replaces the earlier
    // "list ids, then spawn one mime-reader Process per id" shape.
    Process {
        id: listProcess
        command: ["sh", "-c", `
dir="$1"
for m in "$dir"/*.mime; do
  [ -e "$m" ] || continue
  id=$(basename "$m" .mime)
  mime=$(cat "$m" 2>/dev/null)
  first=$(head -n1 "$dir/$id.data" 2>/dev/null | cut -c1-200 | tr -d '\\000\\r\\t')
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
                root.entries = next
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

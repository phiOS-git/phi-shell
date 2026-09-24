import QtQuick
import Quickshell.Io
import qs.Config as Config
import qs.Widgets as Widgets

// The side-slot card for a highlighted result whose action carries an
// image/video path (action.data.path) but no `rich` payload of its own —
// Launcher.qml's richWrap hosts this beside RichResult, mutually exclusive
// with it. An image renders directly; a video gets one ffmpeg-generated
// thumbnail frame, cached by the path's md5 so a repeat highlight is
// instant. An unrecognised extension, an undecodable image or a failed
// thumbnail all show nothing — never an error card, per Launcher.qml's own
// "never invent results in the shell" rule for the query side.

Item {
    id: root

    property string path: ""
    property real chWidth: 8

    // ffmpeg's thumbnail raster width, not a layout size — no design token
    // covers a video-frame decode resolution.
    readonly property int thumbWidth: 480

    readonly property var _imageExts: ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "avif"]
    readonly property var _videoExts: ["mp4", "mkv", "webm", "mov", "avi", "m4v"]
    readonly property string _ext: {
        const i = root.path.lastIndexOf(".")
        return i >= 0 ? root.path.slice(i + 1).toLowerCase() : ""
    }
    readonly property bool _isImage: root._imageExts.indexOf(root._ext) !== -1
    readonly property bool _isVideo: root._videoExts.indexOf(root._ext) !== -1

    // Set once ffmpeg has produced (or already had) a cached thumbnail for
    // the current path; reset on every path change so a stale frame from the
    // previous video never flashes under the new one.
    property string _thumbPath: ""
    // True once previewImage has tried to load and failed (corrupt file, or
    // no decoder for this extension — avif/webp/svg support isn't
    // guaranteed). Reset with every source change.
    property bool _loadFailed: false

    readonly property bool hasContent: root.path.length > 0 && !root._loadFailed
        && (root._isImage || (root._isVideo && root._thumbPath.length > 0))

    implicitHeight: hasContent ? card.implicitHeight : 0
    visible: hasContent

    onPathChanged: {
        root._thumbPath = ""
        root._loadFailed = false
        root._resolveThumb()
    }
    Component.onCompleted: root._resolveThumb()

    function _cacheFileFor(p) {
        return Config.Paths.launcherPreviewCacheDir + "/" + Qt.md5(p) + ".jpg"
    }

    // file:// needs its path segments percent-encoded: a raw "#", "?" or "%"
    // in a filename would otherwise be read as a URL fragment, query or
    // escape instead of a literal character. encodeURIComponent per segment
    // (not the whole path) so "/" stays a separator.
    function _fileUrl(p) {
        return "file://" + p.split("/").map(encodeURIComponent).join("/")
    }

    function _resolveThumb() {
        if (!root._isVideo || root.path.length === 0) return
        root._thumbComponent.createObject(root, {
            targetPath: root.path,
            cachePath: root._cacheFileFor(root.path)
        })
    }

    // One-shot, self-destroying process per resolve — the same shape
    // Launcher.qml's own queryComponent uses, so a fast run through several
    // video results never fights over a single reused Process. A response
    // for a path no longer highlighted (targetPath !== root.path) is simply
    // dropped.
    property Component _thumbComponent: Component {
        Process {
            id: proc
            property string targetPath: ""
            property string cachePath: ""
            // mkdir -p the cache dir, then generate straight to a per-PID
            // temp file and mv it into place: a plain write to the final
            // name would let a highlight-away-and-back race, or an
            // interrupted run, leave a zero-byte or half-written file that
            // [ -s ] would then treat as a permanent cache hit. -y overwrites
            // that temp name only, never the shared cache entry.
            command: ["sh", "-c",
                'f="$1"; c="$2"; d="$3"; w="$4"; mkdir -p "$d" || exit 1; ' +
                'if [ ! -s "$c" ]; then ' +
                't="$c.$$.tmp.jpg"; ' +
                'ffmpeg -y -loglevel error -ss 1 -i "$f" -frames:v 1 -vf "scale=$w:-1" "$t" 2>/dev/null ' +
                '&& mv -f "$t" "$c" || rm -f "$t"; ' +
                'fi; ' +
                '[ -s "$c" ] && printf "%s" "$c"',
                "thumb", proc.targetPath, proc.cachePath,
                Config.Paths.launcherPreviewCacheDir, String(root.thumbWidth)]
            running: true
            onExited: proc.running = false
            stdout: StdioCollector {
                onStreamFinished: {
                    const out = this.text.trim()
                    if (proc.targetPath === root.path && out.length > 0)
                        root._thumbPath = out
                    proc.destroy()
                }
            }
        }
    }

    Widgets.Panel {
        id: card
        width: parent.width
        height: implicitHeight
        implicitHeight: col.implicitHeight + padding * 2
        radius: Config.Appearance.radiusBase

        Column {
            id: col
            width: parent.width
            spacing: root.chWidth * Config.Appearance.space2

            Item {
                id: imageBox
                width: parent.width
                height: Math.min(width * 0.62, root.chWidth * 22)

                Image {
                    id: previewImage
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    // Bounded to the box actually on screen, not the
                    // source's native resolution — a full-size decode of a
                    // large photo for a small side card is wasted work.
                    sourceSize.width: imageBox.width
                    sourceSize.height: imageBox.height
                    source: root._isImage ? root._fileUrl(root.path)
                        : (root._thumbPath.length > 0 ? root._fileUrl(root._thumbPath) : "")
                    onStatusChanged: root._loadFailed = (previewImage.status === Image.Error)
                }
            }

            Widgets.StyledText {
                width: parent.width
                text: {
                    const parts = root.path.split("/")
                    return parts.length > 0 ? parts[parts.length - 1] : root.path
                }
                kind: "label"
                sizeStep: 1
                mono: true
                elide: Text.ElideMiddle
            }
        }
    }
}

import QtQuick
import QtQuick.Pdf

/**
 * PDF for the preview window, loaded on demand like the video view. Qt's own
 * scrollable page view: it scrolls, selects and copies text on its own.
 */
PdfScrollablePageView {
    id: root

    property string path: ""
    property real zoom: 1

    renderScale: root.zoom
    document: PdfDocument {
        source: root.path.length > 0 ? `file://${encodeURI(root.path)}` : ""
    }
}

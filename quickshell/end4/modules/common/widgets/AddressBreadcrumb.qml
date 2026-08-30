import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ListView {
    id: root
    required property var directory
    property var breadcrumbDirectory: ""
    Component.onCompleted: {
        breadcrumbDirectory = directory;
        root.showCurrentDirectory();
    }
    onDirectoryChanged: {
        if (!breadcrumbDirectory.startsWith(directory))
            breadcrumbDirectory = directory;
        root.showCurrentDirectory();
    }

    // A path deep enough to overflow the row would otherwise sit pinned to "/",
    // hiding the one segment that matters -- the folder you are standing in.
    function showCurrentDirectory(): void {
        Qt.callLater(() => root.positionViewAtIndex(directory.split("/").length - 1, ListView.Contain));
    }

    signal navigateToDirectory(string path)

    orientation: ListView.Horizontal
    clip: true
    spacing: 2

    model: breadcrumbDirectory.split("/")
    delegate: SelectionGroupButton {
        id: folderButton
        required property var modelData
        required property int index
        buttonText: index === 0 ? "/" : modelData
        toggled: {
            if (directory.trim() === "/") return index === 0;
            return index === directory.split("/").length - 1
        }
        leftmost: index === 0
        rightmost: index === breadcrumbDirectory.split("/").length - 1

        onClicked: {
            root.navigateToDirectory(breadcrumbDirectory.split("/").slice(0, index + 1).join("/"))
        }
    }
}

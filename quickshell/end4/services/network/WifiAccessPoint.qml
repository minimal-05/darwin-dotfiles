import QtQuick

QtObject {
    required property var lastIpcObject
    readonly property string key: lastIpcObject.key
    readonly property string ssid: lastIpcObject.ssid
    readonly property string bssid: lastIpcObject.bssid
    readonly property int strength: lastIpcObject.strength
    readonly property int frequency: lastIpcObject.frequency
    readonly property bool active: lastIpcObject.active
    readonly property string security: lastIpcObject.security
    readonly property bool isSecure: security.length > 0
    // macOS redacts SSIDs to this literal string without Location Services
    // permission (see Network.qml).
    readonly property bool nameHidden: ssid === "<redacted>"

    property bool askingPassword: false
}

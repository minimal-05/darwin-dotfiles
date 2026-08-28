import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

// Weather, with the five-day forecast on a dropdown. Also the proof that
// PopupWindow anchors correctly on the Cocoa backend.
Pill {
    id: root

    visible: Weather.available
    icon: Weather.icon
    iconColor: Appearance.colors.teal
    text: Weather.label

    onClicked: popup.visible = !popup.visible

    PopupWindow {
        id: popup

        // Anchor with edges + gravity, not by assigning anchor.rect.y —
        // assigning to rect replaces the item-derived rect wholesale and the
        // popup lands at the window origin instead of under the pill.
        anchor.item: root
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 10

        implicitWidth: 250
        implicitHeight: content.implicitHeight + 24
        color: "transparent"
        visible: false

        Rectangle {
            anchors.fill: parent
            radius: 16
            color: Appearance.colors.popup
            border.width: 2
            border.color: Appearance.colors.outline

            Column {
                id: content

                anchors.centerIn: parent
                width: parent.width - 28
                spacing: 8

                Text {
                    text: Weather.place.length > 0 ? Weather.place : "Now"
                    color: Appearance.colors.surfaceFg
                    font.family: Appearance.font.sans
                    font.pixelSize: Appearance.font.large
                    font.weight: Font.Medium
                }

                Text {
                    text: `${Weather.description}  ·  ${Weather.humidity}% humidity  ·  ${Math.round(Weather.windSpeed)} km/h`
                    color: Appearance.colors.muted
                    font.family: Appearance.font.sans
                    font.pixelSize: Appearance.font.small
                    width: parent.width
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Appearance.colors.outline
                }

                Repeater {
                    model: Weather.forecast

                    Row {
                        required property var modelData

                        width: content.width
                        spacing: 10

                        Text {
                            width: 42
                            text: Qt.formatDateTime(new Date(parent.modelData.date), "ddd")
                            color: Appearance.colors.muted
                            font.family: Appearance.font.sans
                            font.pixelSize: Appearance.font.small
                        }

                        Text {
                            text: Weather.wmoIcon[parent.modelData.code] ?? "󰖐"
                            color: Appearance.colors.teal
                            font.family: Appearance.font.icon
                            font.pixelSize: Appearance.font.normal
                        }

                        Text {
                            text: `${Math.round(parent.modelData.max)}° / ${Math.round(parent.modelData.min)}°`
                            color: Appearance.colors.surfaceFg
                            font.family: Appearance.font.sans
                            font.pixelSize: Appearance.font.small
                        }
                    }
                }
            }
        }
    }
}

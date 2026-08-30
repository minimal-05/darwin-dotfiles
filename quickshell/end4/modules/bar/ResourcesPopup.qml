import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    // Helper function to format KB to GB
    function formatKB(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    Row {
        anchors.centerIn: parent
        spacing: 12

        Column {
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow {
                icon: "memory"
                label: "RAM"
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "clock_loader_60"
                    label: Translation.tr("Used:")
                    value: root.formatKB(ResourceUsage.memoryUsed)
                }
                StyledPopupValueRow {
                    icon: "check_circle"
                    label: Translation.tr("Free:")
                    value: root.formatKB(ResourceUsage.memoryFree)
                }
                StyledPopupValueRow {
                    icon: "empty_dashboard"
                    label: Translation.tr("Total:")
                    value: root.formatKB(ResourceUsage.memoryTotal)
                }
            }
        }

        Column {
            visible: ResourceUsage.swapTotal > 0
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow {
                icon: "swap_horiz"
                label: "Swap"
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "clock_loader_60"
                    label: Translation.tr("Used:")
                    value: root.formatKB(ResourceUsage.swapUsed)
                }
                StyledPopupValueRow {
                    icon: "check_circle"
                    label: Translation.tr("Free:")
                    value: root.formatKB(ResourceUsage.swapFree)
                }
                StyledPopupValueRow {
                    icon: "empty_dashboard"
                    label: Translation.tr("Total:")
                    value: root.formatKB(ResourceUsage.swapTotal)
                }
            }
        }

        Column {
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow {
                icon: "planner_review"
                label: "CPU"
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "bolt"
                    label: Translation.tr("Load:")
                    value: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
                }
                Rectangle {
                    width: 140
                    height: 40
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colSecondaryContainer
                    clip: true
                    Canvas {
                        anchors.fill: parent
                        anchors.margins: 2
                        property var values: ResourceUsage.cpuUsageHistory
                        onValuesChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            const step = 4;
                            const cols = Math.floor(width / step);
                            const rows = Math.floor(height / step);
                            for (let c = 0; c < cols; ++c) {
                                const v = values[values.length - cols + c];
                                if (v === undefined)
                                    continue;
                                // ponytail: colour per column, so a spike keeps its red as it scrolls off
                                ctx.fillStyle = ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colPrimary, v);
                                for (let r = 0; r < Math.ceil(v * rows); ++r) {
                                    ctx.beginPath();
                                    ctx.arc(c * step + step / 2, height - (r * step + step / 2), 1.4, 0, 2 * Math.PI);
                                    ctx.fill();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

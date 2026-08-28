pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Open-Meteo with IP geolocation, carried over from the SketchyBar config.
// Open-Meteo auto-selects the best national model (JMA in Japan); wttr.in was
// consistently a few degrees off.
Singleton {
    id: root

    property real temperature: 0
    property int code: -1
    property real windSpeed: 0
    property int humidity: 0
    property string place: ""
    property list<var> forecast: []

    readonly property bool available: code >= 0

    readonly property var wmoIcon: ({
            0: "󰖙",
            1: "󰖕",
            2: "󰖕",
            3: "󰖐",
            45: "󰖑",
            48: "󰖑",
            51: "󰖗",
            53: "󰖗",
            55: "󰖗",
            56: "󰖗",
            57: "󰖗",
            61: "󰖖",
            63: "󰖖",
            65: "󰖖",
            66: "󰖖",
            67: "󰖖",
            71: "󰖘",
            73: "󰖘",
            75: "󰖘",
            77: "󰖘",
            80: "󰖖",
            81: "󰖖",
            82: "󰖖",
            85: "󰖘",
            86: "󰖘",
            95: "󰖓",
            96: "󰖓",
            99: "󰖓"
        })

    readonly property var wmoName: ({
            0: "Clear",
            1: "Mostly clear",
            2: "Partly cloudy",
            3: "Overcast",
            45: "Fog",
            48: "Fog",
            51: "Drizzle",
            53: "Drizzle",
            55: "Drizzle",
            56: "Drizzle",
            57: "Drizzle",
            61: "Rain",
            63: "Rain",
            65: "Heavy rain",
            66: "Freezing rain",
            67: "Freezing rain",
            71: "Snow",
            73: "Snow",
            75: "Heavy snow",
            77: "Snow",
            80: "Showers",
            81: "Showers",
            82: "Heavy showers",
            85: "Snow showers",
            86: "Snow showers",
            95: "Thunderstorm",
            96: "Thunderstorm",
            99: "Thunderstorm"
        })

    readonly property string icon: wmoIcon[code] ?? "󰖐"
    readonly property string description: wmoName[code] ?? "—"
    readonly property string label: available ? `${Math.round(temperature)}°C` : "…"

    property real latitude: 0
    property real longitude: 0

    function refresh(): void {
        if (latitude === 0 && longitude === 0)
            locate.running = true;
        else
            fetch.running = true;
    }

    // IP geolocation. Coarse, but it costs no permission prompt — CoreLocation
    // would need Location access and therefore a signed .app bundle.
    // ipinfo.io rather than ipapi.co: the latter rate-limits free callers hard.
    Process {
        id: locate

        running: true
        command: ["curl", "-sm", "5", "https://ipinfo.io"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    const parts = (data.loc ?? "").split(",");
                    if (parts.length !== 2)
                        return;

                    const lat = parseFloat(parts[0]);
                    const lon = parseFloat(parts[1]);
                    if (isNaN(lat) || isNaN(lon))
                        return;

                    root.latitude = lat;
                    root.longitude = lon;
                    root.place = data.city ?? "";
                    fetch.running = true;
                } catch (e) {}
            }
        }
    }

    Process {
        id: fetch

        command: ["curl", "-s", "--max-time", "8", `https://api.open-meteo.com/v1/forecast?latitude=${root.latitude}&longitude=${root.longitude}&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=5`]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    const cur = data.current;
                    if (!cur)
                        return;

                    root.temperature = cur.temperature_2m ?? 0;
                    root.humidity = cur.relative_humidity_2m ?? 0;
                    root.windSpeed = cur.wind_speed_10m ?? 0;
                    root.code = cur.weather_code ?? -1;

                    const daily = data.daily;
                    if (daily && Array.isArray(daily.time)) {
                        root.forecast = daily.time.map((day, i) => ({
                                    date: day,
                                    code: daily.weather_code[i],
                                    max: daily.temperature_2m_max[i],
                                    min: daily.temperature_2m_min[i]
                                }));
                    }
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 900000     // 15 minutes
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}

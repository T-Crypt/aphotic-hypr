pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Open-Meteo (no API key) weather for the Dashboard's weather card.
// Geocodes Settings.weatherLocation once (or falls back to IP-based
// approximate location once) and caches the resolved lat/lon -- never
// re-geocodes on a plain refresh, only when the location string itself
// changes. Polls the forecast on a 20-minute Timer (not live-polling) and
// keeps the last-good response on any fetch failure rather than blanking
// the card; both the resolved location and the last-good forecast persist
// to disk (same FileView load/save pattern as Settings.qml) so a fresh
// shell start shows the last known weather immediately instead of a
// blank card while the first real fetch is in flight.
Singleton {
    id: root

    readonly property string statePath: `${Quickshell.env("HOME")}/.local/state/aphotic/weather-cache.json`

    property real lat: NaN
    property real lon: NaN
    property string resolvedLocationName: ""
    property string _geocodedFor: ""

    property real currentTemp: NaN
    property string conditionText: ""
    property int conditionCode: -1
    property var forecast: []
    property string lastUpdated: ""
    property string errorText: ""

    property bool _loaded: false
    property bool _writePending: false
    property bool refreshing: false

    readonly property bool hasData: !isNaN(root.currentTemp)

    function _iconFor(code: int): string {
        if (code === 0)
            return "sunny";
        if (code >= 1 && code <= 3)
            return "cloud";
        if (code === 45 || code === 48)
            return "foggy";
        if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82))
            return "rainy";
        if ((code >= 71 && code <= 77) || code === 85 || code === 86)
            return "ac_unit";
        if (code >= 95)
            return "thunderstorm";
        return "cloud";
    }

    readonly property string conditionIcon: root._iconFor(root.conditionCode)

    function _conditionTextFor(code: int): string {
        if (code === 0)
            return qsTr("Clear");
        if (code >= 1 && code <= 3)
            return qsTr("Cloudy");
        if (code === 45 || code === 48)
            return qsTr("Foggy");
        if (code >= 51 && code <= 57)
            return qsTr("Drizzle");
        if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82))
            return qsTr("Rain");
        if ((code >= 71 && code <= 77) || code === 85 || code === 86)
            return qsTr("Snow");
        if (code >= 95)
            return qsTr("Thunderstorm");
        return qsTr("Unknown");
    }

    function refresh(): void {
        if (root.refreshing)
            return;
        const location = Settings.weatherLocation.trim();
        if (location.length > 0 && location !== root._geocodedFor) {
            root.refreshing = true;
            geocodeProc.command = ["curl", "-s", "-m", "10", `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(location)}&count=1&language=en&format=json`];
            geocodeProc.running = true;
        } else if (isNaN(root.lat) && location.length === 0) {
            root.refreshing = true;
            ipLocateProc.command = ["curl", "-s", "-m", "10", "http://ip-api.com/json/"];
            ipLocateProc.running = true;
        } else if (!isNaN(root.lat)) {
            root._fetchForecast();
        }
    }

    function _fetchForecast(): void {
        root.refreshing = true;
        const units = Settings.weatherUnits === "fahrenheit" ? "fahrenheit" : "celsius";
        forecastProc.command = ["curl", "-s", "-m", "10", `https://api.open-meteo.com/v1/forecast?latitude=${root.lat}&longitude=${root.lon}&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min,weather_code&temperature_unit=${units}&timezone=auto&forecast_days=3`];
        forecastProc.running = true;
    }

    function _save(): void {
        if (!root._loaded)
            return;
        root._writePending = true;
        stateWriter.setText(JSON.stringify({
            lat: root.lat,
            lon: root.lon,
            resolvedLocationName: root.resolvedLocationName,
            geocodedFor: root._geocodedFor,
            currentTemp: root.currentTemp,
            conditionCode: root.conditionCode,
            forecast: root.forecast,
            lastUpdated: root.lastUpdated
        }, null, 2));
    }

    Process {
        id: geocodeProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    const first = data?.results?.[0];
                    if (!first)
                        throw new Error("no geocoding results");
                    root.lat = first.latitude;
                    root.lon = first.longitude;
                    root.resolvedLocationName = first.name;
                    root._geocodedFor = Settings.weatherLocation.trim();
                    root._save();
                    root._fetchForecast();
                } catch (e) {
                    root.errorText = qsTr("Could not find location: %1").arg(Settings.weatherLocation);
                    root.refreshing = false;
                }
            }
        }
    }

    Process {
        id: ipLocateProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (typeof data.lat !== "number" || typeof data.lon !== "number")
                        throw new Error("no ip-based location");
                    root.lat = data.lat;
                    root.lon = data.lon;
                    root.resolvedLocationName = [data.city, data.regionName].filter(s => s).join(", ");
                    root._geocodedFor = "";
                    root._save();
                    root._fetchForecast();
                } catch (e) {
                    root.errorText = qsTr("Could not determine location automatically. Set one in Settings.");
                    root.refreshing = false;
                }
            }
        }
    }

    Process {
        id: forecastProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.currentTemp = data.current.temperature_2m;
                    root.conditionCode = data.current.weather_code;
                    root.conditionText = root._conditionTextFor(root.conditionCode);
                    const days = data.daily.time;
                    root.forecast = days.map((day, i) => ({
                                day,
                                high: data.daily.temperature_2m_max[i],
                                low: data.daily.temperature_2m_min[i],
                                code: data.daily.weather_code[i]
                            }));
                    root.lastUpdated = new Date().toISOString();
                    root.errorText = "";
                    root._save();
                } catch (e) {
                    root.errorText = qsTr("Weather unavailable (network or API error)");
                    // Keep the last-good currentTemp/forecast as-is -- a
                    // failed refresh shouldn't blank a working card.
                }
                root.refreshing = false;
            }
        }
    }

    FileView {
        id: stateFile

        path: root.statePath
        watchChanges: true
        onLoaded: {
            if (root._writePending) {
                root._writePending = false;
                return;
            }
            try {
                const data = JSON.parse(text());
                if (typeof data.lat === "number")
                    root.lat = data.lat;
                if (typeof data.lon === "number")
                    root.lon = data.lon;
                if (typeof data.resolvedLocationName === "string")
                    root.resolvedLocationName = data.resolvedLocationName;
                if (typeof data.geocodedFor === "string")
                    root._geocodedFor = data.geocodedFor;
                if (typeof data.currentTemp === "number")
                    root.currentTemp = data.currentTemp;
                if (typeof data.conditionCode === "number") {
                    root.conditionCode = data.conditionCode;
                    root.conditionText = root._conditionTextFor(root.conditionCode);
                }
                if (Array.isArray(data.forecast))
                    root.forecast = data.forecast;
                if (typeof data.lastUpdated === "string")
                    root.lastUpdated = data.lastUpdated;
            } catch (e) {
                // First run / empty file -- keep the defaults above.
            }
            root._loaded = true;
            root.refresh();
        }
        onLoadFailed: error => {
            root._loaded = true;
            root.refresh();
        }
    }

    FileView {
        id: stateWriter

        path: root.statePath
        printErrors: false
    }

    Process {
        id: mkStateDir
        command: ["mkdir", "-p", `${Quickshell.env("HOME")}/.local/state/aphotic`]
        onExited: stateFile.reload()
    }

    Timer {
        interval: 20 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Connections {
        target: Settings
        function onWeatherLocationChanged() {
            root.refresh();
        }
        function onWeatherUnitsChanged() {
            if (!isNaN(root.lat))
                root._fetchForecast();
        }
    }

    Component.onCompleted: mkStateDir.running = true
}

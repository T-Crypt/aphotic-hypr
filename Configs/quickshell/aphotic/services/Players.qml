pragma Singleton

import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.config
import "../utils/MediaNotifications.js" as MediaNotifications

Singleton {
    id: root

    readonly property list<MprisPlayer> list: Mpris.players.values
    readonly property MprisPlayer active: props.manualActive ?? list.find(p => getIdentity(p) === GlobalConfig.services.defaultPlayer) ?? list[0] ?? null
    property alias manualActive: props.manualActive

    // Dedup key for progressive metadata (e.g. mpv-mpris/yt-dlp player fills title then artist later).
    property string lastNowPlayingKey: ""
    readonly property real audibleThreshold: 0.001
    readonly property bool hasPendingNowPlaying: {
        const player = root.active;
        if (!GlobalConfig.utilities.toasts.nowPlaying || !player)
            return false;
        return MediaNotifications.shouldNotify(player, true, root.lastNowPlayingKey, root.getIdentity(player));
    }

    function getIdentity(player: MprisPlayer): string {
        if (!player)
            return "";
        const alias = GlobalConfig.services.playerAliases.find(a => a.from === player.identity);
        return alias?.to ?? player.identity;
    }

    function getArtUrl(player: MprisPlayer): string {
        if (!player)
            return "";
        if (player.trackArtUrl)
            return player.trackArtUrl;

        const url = player.metadata["xesam:url"] ?? "";
        if (url.startsWith("https://www.youtube.com/watch")) {
            // Fallback for youtube
            const id = url.match(/[?&]v=([\w-]{11})/)?.[1];
            return id ? `https://img.youtube.com/vi/${id}/hqdefault.jpg` : "";
        }
        return "";
    }

    // Quickshell only emits postTrackChanged when trackid/url/title change, so late
    // artist updates (common with mpv-mpris + yt-dlp player) never retrigger it. Watch
    // title/artist too and toast once both are usable.
    function maybeToastNowPlaying(): void {
        if (!GlobalConfig.utilities.toasts.nowPlaying)
            return;

        const player = root.active;
        if (!player)
            return;

        const monitors = [];
        for (let i = 0; i < peakMonitors.count; ++i) {
            const monitor = peakMonitors.objectAt(i);
            if (monitor)
                monitors.push(monitor);
        }
        const audible = MediaNotifications.hasAudibleOutput(player, monitors, audibleThreshold, getIdentity(player), PwNodeType.AudioOutStream);

        if (!MediaNotifications.shouldNotify(player, audible, lastNowPlayingKey, getIdentity(player)))
            return;

        const source = MediaNotifications.sourceFor(player, getIdentity(player));
        const icon = MediaNotifications.firstAvailableIcon(source.iconCandidates, candidate => !!Quickshell.iconPath(candidate, true), "music_note");
        lastNowPlayingKey = MediaNotifications.trackKey(player, getIdentity(player));
        Toaster.toastFrom(source.name, qsTr("Now Playing"), qsTr("%1 - %2").arg(player.trackArtist).arg(player.trackTitle), icon);
    }

    onActiveChanged: lastNowPlayingKey = ""

    Connections {
        function onPostTrackChanged(): void {
            root.maybeToastNowPlaying();
        }

        function onTrackTitleChanged(): void {
            root.maybeToastNowPlaying();
        }

        function onTrackArtistChanged(): void {
            root.maybeToastNowPlaying();
        }

        function onIsPlayingChanged(): void {
            root.maybeToastNowPlaying();
        }

        target: root.active
    }

    Instantiator {
        id: peakMonitors

        model: root.hasPendingNowPlaying ? Audio.streams.filter(stream => MediaNotifications.isOutputStream(stream, PwNodeType.AudioOutStream)) : []

        delegate: PwNodePeakMonitor {
            required property var modelData

            node: modelData
            enabled: true
            onPeakChanged: root.maybeToastNowPlaying()
        }
    }

    PersistentProperties {
        id: props

        property MprisPlayer manualActive

        reloadableId: "players"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaToggle"
        description: "Toggle media playback"
        onPressed: {
            const active = root.active;
            if (active && active.canTogglePlaying)
                active.togglePlaying();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaPrev"
        description: "Previous track"
        onPressed: {
            const active = root.active;
            if (active && active.canGoPrevious)
                active.previous();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaNext"
        description: "Next track"
        onPressed: {
            const active = root.active;
            if (active && active.canGoNext)
                active.next();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaStop"
        description: "Stop media playback"
        onPressed: root.active?.stop()
    }

    IpcHandler {
        function getActive(prop: string): string {
            const active = root.active;
            return active ? active[prop] ?? "Invalid property" : "No active player";
        }

        function list(): string {
            return root.list.map(p => root.getIdentity(p)).join("\n");
        }

        function play(): void {
            const active = root.active;
            if (active?.canPlay)
                active.play();
        }

        function pause(): void {
            const active = root.active;
            if (active?.canPause)
                active.pause();
        }

        function playPause(): void {
            const active = root.active;
            if (active?.canTogglePlaying)
                active.togglePlaying();
        }

        function previous(): void {
            const active = root.active;
            if (active?.canGoPrevious)
                active.previous();
        }

        function next(): void {
            const active = root.active;
            if (active?.canGoNext)
                active.next();
        }

        function stop(): void {
            root.active?.stop();
        }

        target: "mpris"
    }
}

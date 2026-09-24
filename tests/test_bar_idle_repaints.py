from pathlib import Path


QML = Path(__file__).parents[1] / "Configs/quickshell/aphotic"


def read(relative_path: str) -> str:
    return (QML / relative_path).read_text()


def test_active_indicator_glow_is_static_at_the_pulse_mean():
    source = read("modules/bar/components/workspaces/ActiveIndicator.qml")

    assert "breathing: false" in source
    assert "intensity: DepthFx.glowIntensity * 0.725" in source


def test_bluetooth_connecting_blink_is_bounded():
    source = read("modules/bar/components/status/BluetoothStatus.qml")

    assert "state === BluetoothDeviceState.Connecting" in source
    assert "loops: 3" in source
    assert "loops: Animation.Infinite" not in source


def test_time_uses_minute_precision_without_losing_seconds():
    source = read("services/Time.qml")

    assert "precision: SystemClock.Minutes" in source
    assert "precision: SystemClock.Seconds" in source
    assert 'fmt.includes("s") ? secondsClock.date : minuteClock.date' in source


def test_system_usage_base_poll_follows_mounted_readers():
    service = read("services/SystemUsage.qml")
    watch = read("components/SystemUsageWatch.qml")

    assert "running: root.wanted" in service
    assert "function subscribe()" in service
    assert "function unsubscribe()" in service
    assert "SystemUsage.subscribe()" in watch
    assert "SystemUsage.unsubscribe()" in watch
    for consumer in (
        "modules/bar/components/status/ResourcesStatus.qml",
        "modules/notch/NotchIdleStrip.qml",
    ):
        source = read(consumer)
        assert "SystemUsageWatch" in source
        assert "detailed: false" in source


def test_keyboard_poll_follows_mounted_readers():
    service = read("services/Hypr.qml")
    watch = read("components/KeyboardStateWatch.qml")
    qmldir = read("components/qmldir")

    assert "running: root.keyboardStateWanted" in service
    assert "function subscribeKeyboardState()" in service
    assert "function unsubscribeKeyboardState()" in service
    assert "Hypr.subscribeKeyboardState()" in watch
    assert "Hypr.unsubscribeKeyboardState()" in watch
    assert "KeyboardStateWatch 1.0 KeyboardStateWatch.qml" in qmldir
    for consumer in (
        "modules/bar/components/status/LockStatus.qml",
        "modules/bar/components/StatusIcons.qml",
        "modules/bar/popouts/LockStatusPopout.qml",
        "modules/bar/popouts/KbLayoutPopout.qml",
    ):
        assert "KeyboardStateWatch" in read(consumer)

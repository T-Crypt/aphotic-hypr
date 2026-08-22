import QtQuick

// Hand-drawn HSV wheel: angle = hue, radius = saturation. `value`
// (brightness) is fed in from outside (a slider) rather than picked on
// the wheel itself, same split every other HSV picker uses. Draws once
// per `value`/size change via a per-pixel ImageData buffer -- cheap
// enough for a picker that isn't open every frame.
Item {
    id: root

    property real hue: 0
    property real saturation: 0
    property real value: 1

    readonly property color pickedColor: Qt.hsva(hue, saturation, value, 1)

    signal picked(color: color)

    implicitWidth: 160
    implicitHeight: 160

    function _angleToHue(angle: real): real {
        const raw = angle / (2 * Math.PI) + 1;
        return raw - Math.floor(raw);
    }

    Canvas {
        id: canvas

        anchors.fill: parent

        property real paintedValue: root.value
        onPaintedValueChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            const w = width, h = height;
            if (w <= 0 || h <= 0)
                return;
            const img = ctx.createImageData(w, h);
            const data = img.data;
            const cx = w / 2, cy = h / 2, r = Math.min(cx, cy);

            for (let y = 0; y < h; y++) {
                for (let x = 0; x < w; x++) {
                    const dx = x - cx + 0.5;
                    const dy = y - cy + 0.5;
                    const dist = Math.sqrt(dx * dx + dy * dy);
                    const idx = (y * w + x) * 4;
                    if (dist > r) {
                        data[idx + 3] = 0;
                        continue;
                    }
                    const hue = root._angleToHue(Math.atan2(dy, dx));
                    const sat = Math.min(1, dist / r);
                    const col = Qt.hsva(hue, sat, canvas.paintedValue, 1);
                    data[idx] = Math.round(col.r * 255);
                    data[idx + 1] = Math.round(col.g * 255);
                    data[idx + 2] = Math.round(col.b * 255);
                    data[idx + 3] = 255;
                }
            }
            ctx.putImageData(img, 0, 0);
        }

        Component.onCompleted: requestPaint()
    }

    Rectangle {
        id: handle

        readonly property real _r: Math.min(canvas.width, canvas.height) / 2

        width: 18
        height: 18
        radius: 9
        color: root.pickedColor
        border.width: 2
        border.color: "#ffffff"
        x: canvas.width / 2 + Math.cos(root.hue * 2 * Math.PI) * root.saturation * _r - width / 2
        y: canvas.height / 2 + Math.sin(root.hue * 2 * Math.PI) * root.saturation * _r - height / 2
    }

    MouseArea {
        anchors.fill: canvas

        function updateFromPos(mx: real, my: real): void {
            const cx = canvas.width / 2, cy = canvas.height / 2, r = Math.min(cx, cy);
            const dx = mx - cx, dy = my - cy;
            const dist = Math.min(r, Math.sqrt(dx * dx + dy * dy));
            root.hue = root._angleToHue(Math.atan2(dy, dx));
            root.saturation = r > 0 ? dist / r : 0;
            root.picked(root.pickedColor);
        }

        onPressed: mouse => updateFromPos(mouse.x, mouse.y)
        onPositionChanged: mouse => {
            if (pressed)
                updateFromPos(mouse.x, mouse.y);
        }
    }
}

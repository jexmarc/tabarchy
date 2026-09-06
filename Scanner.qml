import QtQuick
import qs.Commons

// Knight Rider KITT scanner: a hot LED that travels the bar and back.
Item {
  id: root

  property bool running: false
  property int cells: 9
  property color led: Color.accent
  property int duration: 720

  readonly property int cellSize: Math.max(2, Math.round(height * 0.72))
  readonly property int gap: Math.max(1, Math.round(cellSize * 0.28))

  implicitWidth: cells * cellSize + Math.max(0, cells - 1) * gap
  implicitHeight: Style.space(10)

  property real head: 0

  SequentialAnimation on head {
    running: root.running && root.visible
    loops: Animation.Infinite
    NumberAnimation { from: 0; to: 1; duration: root.duration; easing.type: Easing.InOutSine }
    NumberAnimation { from: 1; to: 0; duration: root.duration; easing.type: Easing.InOutSine }
    onRunningChanged: if (!running) root.head = 0
  }

  Row {
    anchors.centerIn: parent
    spacing: root.gap

    Repeater {
      model: root.cells
      delegate: Rectangle {
        required property int index
        width: root.cellSize
        height: root.cellSize
        radius: Math.max(0, Math.round(root.cellSize * 0.15))
        color: root.led
        opacity: {
          if (!root.running) return 0.06
          var pos = index / Math.max(1, root.cells - 1)
          var d = Math.abs(pos - root.head)
          if (d < 0.07) return 1
          if (d < 0.18) return 0.55
          if (d < 0.32) return 0.22
          return 0.06
        }
      }
    }
  }
}

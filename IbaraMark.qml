import QtQuick
import QtQuick.Shapes
import qs.Commons

// Exact paths from the design reference. The rear never enters the front
// footprint; the i is transparent, not painted with an assumed background.
Item {
  id: root
  property color color: Color.foreground
  property bool compact: width <= Style.space(32)
  implicitWidth: Style.space(32)
  implicitHeight: implicitWidth
  Accessible.ignored: true

  Shape {
    width: root.compact ? 32 : 128
    height: width
    anchors.centerIn: parent
    scale: Math.min(root.width, root.height) / width
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: "transparent"
      fillColor: root.color
      PathSvg { path: root.compact ? "M6 5H23V10H20V8H9V19H11V22H6Z" : "M24 20H90V40H80V30H34V76H44V86H24Z" }
    }
    ShapePath {
      strokeColor: "transparent"
      fillColor: root.color
      fillRule: ShapePath.OddEvenFill
      PathSvg { path: root.compact ? "M11 10H28V27H11Z M17 13H21V17H17Z M17 18H21V25H17Z" : "M44 40H110V106H44Z M70 54H82V66H70Z M70 71H82V96H70Z" }
    }
  }
}

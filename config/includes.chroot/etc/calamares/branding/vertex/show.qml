import QtQuick 2.0

// Vertex Linux — minimal single-slide installer slideshow.
// Replace/expand this once real marketing art exists; for now it just
// shows the brand mark on a gradient that matches the sidebar.

Rectangle {
    id: slideshow
    anchors.fill: parent
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#2E1065" }
        GradientStop { position: 1.0; color: "#4C1D95" }
    }

    Image {
        anchors.centerIn: parent
        width: parent.width * 0.35
        height: width
        fillMode: Image.PreserveAspectFit
        source: "images/logo.png"
    }

    Text {
        anchors.top: parent.verticalCenter
        anchors.topMargin: parent.height * 0.22
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Installing Vertex Linux..."
        color: "#F5F3FF"
        font.pixelSize: 20
    }

    function nextSlide() {}
    Component.onCompleted: nextSlide()
}

import SwiftUI

/// SwiftUI overlay for the Phase A virtual-finish-line detection overlay.
///
/// Behaviour:
/// - If no `detectionLine` exists yet, the whole overlay area is a draw target:
///   click-and-drag to define p1 → p2.
/// - Once a line exists, two endpoint handles (filled cyan) are draggable, and
///   the line body itself accepts a bodily drag (translates both endpoints together).
/// - Lane divider ticks are drawn at t = k / laneCount for k = 1..laneCount-1.
struct DetectionLineOverlayView: View {
    @ObservedObject var playerViewModel: PlayerViewModel

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let line = playerViewModel.detectionLine {
                    let p1 = absolute(line.p1, in: geo.size)
                    let p2 = absolute(line.p2, in: geo.size)

                    // Bodily-drag hit area along the line (drawn underneath handles).
                    Path { path in
                        path.move(to: p1)
                        path.addLine(to: p2)
                    }
                    .stroke(Color.cyan.opacity(0.001), lineWidth: 18)  // wide invisible hit area
                    .contentShape(Rectangle())
                    .gesture(bodilyDragGesture(geoSize: geo.size))

                    // Visible line.
                    Path { path in
                        path.move(to: p1)
                        path.addLine(to: p2)
                    }
                    .stroke(Color.cyan, lineWidth: 2)
                    .allowsHitTesting(false)

                    // Endpoint handles (filled cyan, draggable).
                    endpointHandle(at: p1, which: 1, viewSize: geo.size)
                    endpointHandle(at: p2, which: 2, viewSize: geo.size)
                } else {
                    // Draw mode: capture a drag to define the line.
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 4)
                                .onChanged { value in
                                    let p1 = normalize(value.startLocation, in: geo.size)
                                    let p2 = normalize(value.location, in: geo.size)
                                    playerViewModel.setDetectionLine(p1: p1, p2: p2)
                                }
                        )
                        .overlay(
                            // Hint text shown when no line exists yet.
                            VStack {
                                Spacer()
                                Text("Click & drag across the finish buoys to define the detection line")
                                    .font(.caption)
                                    .foregroundColor(.cyan)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.black.opacity(0.55))
                                    .cornerRadius(4)
                                    .padding(.bottom, 12)
                            }
                            .allowsHitTesting(false)
                        )
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func endpointHandle(at point: CGPoint, which: Int, viewSize: CGSize) -> some View {
        Circle()
            .fill(Color.cyan)
            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
            .frame(width: 14, height: 14)
            .position(point)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let n = normalize(value.location, in: viewSize)
                        playerViewModel.setDetectionLineEndpoint(which, to: n)
                    }
            )
    }

    private func bodilyDragGesture(geoSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                playerViewModel.beginDetectionLineDrag()  // idempotent — captures start once
                let normTranslation = CGSize(
                    width: value.translation.width / max(1, geoSize.width),
                    height: value.translation.height / max(1, geoSize.height)
                )
                playerViewModel.updateDetectionLineDrag(translationNormalized: normTranslation)
            }
            .onEnded { _ in
                playerViewModel.endDetectionLineDrag()
            }
    }

    // MARK: - Coord conversion

    private func absolute(_ n: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: n.x * size.width, y: n.y * size.height)
    }

    private func normalize(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: max(0, min(1, p.x / max(1, size.width))),
                y: max(0, min(1, p.y / max(1, size.height))))
    }
}

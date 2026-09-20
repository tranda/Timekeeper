import SwiftUI

/// The yellow photo-finish line plus its two red endpoint handles, drawn over
/// the video rectangle.
///
/// Used in BOTH modes:
///  - LIVE: the line is a property of the physical camera placement, so it is
///    set once while watching the live feed, before any race is recorded.
///  - REVIEW: fine-tuning against the recorded clip.
///
/// Both call sites share the same `PlayerViewModel`, so the position (and its
/// UserDefaults / session persistence) is identical in either mode.
///
/// Geometry contract: the overlay spans the WHOLE rect it is given and maps
/// `x = width * normalizedX`, `y ∈ {0, height}`. The caller must therefore size
/// it to exactly the video rectangle (both call sites use a fixed 16:9 frame).
struct FinishLineOverlay: View {
    @ObservedObject var playerViewModel: PlayerViewModel

    // Captured finishLineTopX / finishLineBottomX at the moment a handle drag
    // starts. Drag deltas (value.translation.width) get added to this baseline
    // so the line follows the pointer 1:1 from the moment it's grabbed —
    // without the apparent "snap" the absolute-location code used to produce
    // (value.location for a 12pt handle is in the handle's local space, so
    // dividing by video width turned the cursor's offset-within-handle into
    // a near-zero normalized X, and the handle jumped on first touch).
    @State private var topHandleDragStartX: Double? = nil
    @State private var bottomHandleDragStartX: Double? = nil

    var body: some View {
        GeometryReader { videoGeometry in
            ZStack {
                // Finish line - positioned at edges for Y coordinate testing
                Path { path in
                    let topX = videoGeometry.size.width * playerViewModel.finishLineTopX
                    let topY: CGFloat = 0 // Top edge
                    let bottomX = videoGeometry.size.width * playerViewModel.finishLineBottomX
                    let bottomY = videoGeometry.size.height // Bottom edge

                    path.move(to: CGPoint(x: topX, y: topY))
                    path.addLine(to: CGPoint(x: bottomX, y: bottomY))
                }
                .stroke(Color.yellow, lineWidth: 1)
                .gesture(
                    // minimumDistance: 0 → fine-grained drag from the first pixel,
                    // no 10pt dead-zone-then-jump that feels like snapping.
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let startX = value.startLocation.x / videoGeometry.size.width
                            let currentX = value.location.x / videoGeometry.size.width
                            playerViewModel.updateLineDragWithDelta(startX: startX, currentX: currentX)
                        }
                        .onEnded { _ in
                            playerViewModel.endLineDrag()
                        }
                )

                // Top handle - positioned at top edge
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .position(
                        x: videoGeometry.size.width * playerViewModel.finishLineTopX,
                        y: 0 // Top edge
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if topHandleDragStartX == nil {
                                    topHandleDragStartX = playerViewModel.finishLineTopX
                                    // Flag drag-in-progress so the session observer doesn't
                                    // overwrite our value mid-drag (see PlayerViewModel.observeSessionFinishLine).
                                    playerViewModel.startLineDrag()
                                }
                                let dx = Double(value.translation.width) / Double(videoGeometry.size.width)
                                playerViewModel.setFinishLineTopX(topHandleDragStartX! + dx)
                            }
                            .onEnded { _ in
                                topHandleDragStartX = nil
                                playerViewModel.endLineDrag()
                            }
                    )

                // Bottom handle - positioned at bottom edge
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .position(
                        x: videoGeometry.size.width * playerViewModel.finishLineBottomX,
                        y: videoGeometry.size.height // Bottom edge
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if bottomHandleDragStartX == nil {
                                    bottomHandleDragStartX = playerViewModel.finishLineBottomX
                                    playerViewModel.startLineDrag()
                                }
                                let dx = Double(value.translation.width) / Double(videoGeometry.size.width)
                                playerViewModel.setFinishLineBottomX(bottomHandleDragStartX! + dx)
                            }
                            .onEnded { _ in
                                bottomHandleDragStartX = nil
                                playerViewModel.endLineDrag()
                            }
                    )
            }
        }
    }
}

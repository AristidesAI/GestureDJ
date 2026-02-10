//
//  GestureCanvasView.swift
//  GestureFlow
//
//  Created by aristides lintzeris on 10/2/2026.
//


import SwiftUI
import Vision

struct GestureCanvasView: View {
    @EnvironmentObject var visionEngine: VisionEngine

    var body: some View {
        // Use GeometryReader to get the size of the view for coordinate conversion.
        GeometryReader { geometry in
            Canvas { context, size in
                for landmarks in visionEngine.handLandmarks {
                    let thumbPoint = landmarks.thumbTip.map { convertToViewCoordinates(point: $0, geometry: geometry) }
                    let indexPoint = landmarks.indexTip.map { convertToViewCoordinates(point: $0, geometry: geometry) }
                    
                    if let thumb = thumbPoint, let index = indexPoint {
                        // 1. Connection line (behind dots)
                        var path = Path()
                        path.move(to: thumb)
                        path.addLine(to: index)
                        context.stroke(path, with: .color(.white.opacity(0.3)), lineWidth: 2)
                        
                        // 2. Horizontal Baseline (Zero Point) at midpoint
                        let midpoint = CGPoint(x: (thumb.x + index.x) / 2, y: (thumb.y + index.y) / 2)
                        var horizontalPath = Path()
                        horizontalPath.move(to: CGPoint(x: midpoint.x - 30, y: midpoint.y))
                        horizontalPath.addLine(to: CGPoint(x: midpoint.x + 30, y: midpoint.y))
                        context.stroke(horizontalPath, with: .color(.white), lineWidth: 3)
                        
                        // 3. Ruler Ticks (Up and Down from Midpoint)
                        let tickDist: CGFloat = 20
                        let tickWidth: CGFloat = 8
                        drawRuler(context: context, from: midpoint, towards: index, tickDist: tickDist, tickWidth: tickWidth)
                        drawRuler(context: context, from: midpoint, towards: thumb, tickDist: tickDist, tickWidth: tickWidth)
                        
                        // 4. Thumb and Index Dots
                        let dotSize: CGFloat = 16
                        context.fill(Path(ellipseIn: CGRect(x: thumb.x - dotSize/2, y: thumb.y - dotSize/2, width: dotSize, height: dotSize)), with: .color(.white))
                        context.fill(Path(ellipseIn: CGRect(x: index.x - dotSize/2, y: index.y - dotSize/2, width: dotSize, height: dotSize)), with: .color(.white))
                    }
                }
            }
        }
    }
    
    private func drawRuler(context: GraphicsContext, from: CGPoint, towards: CGPoint, tickDist: CGFloat, tickWidth: CGFloat) {
        let dx = towards.x - from.x
        let dy = towards.y - from.y
        let distance = sqrt(dx*dx + dy*dy)
        if distance < tickDist { return }
        
        let steps = Int(distance / tickDist)
        for i in 1...steps {
            let ratio = (CGFloat(i) * tickDist) / distance
            let tx = from.x + dx * ratio
            let ty = from.y + dy * ratio
            
            // Perpendicular vector for the tick
            let normalX = -dy / distance
            let normalY = dx / distance
            
            var tickPath = Path()
            tickPath.move(to: CGPoint(x: tx - normalX * tickWidth, y: ty - normalY * tickWidth))
            tickPath.addLine(to: CGPoint(x: tx + normalX * tickWidth, y: ty + normalY * tickWidth))
            
            context.stroke(tickPath, with: .color(.white.opacity(0.4)), lineWidth: 1)
        }
    }
    
    // Convert Vision's normalized coordinates (bottom-left origin) to SwiftUI's
    // view coordinates (top-left origin).
    private func convertToViewCoordinates(point: CGPoint, geometry: GeometryProxy) -> CGPoint {
        let viewSize = geometry.size
        
        // Vision coordinates are normalized [0,1] from the camera buffer.
        // Front camera is mirrored, so x=0 is the physical right (which should be screen right).
        
        let bufferRatio: CGFloat = 4.0 / 3.0 // Portrait buffer (Height / Width)
        let viewRatio: CGFloat = viewSize.height / viewSize.width
        
        var xOffset: CGFloat = 0
        var yOffset: CGFloat = 0
        var scale: CGFloat = 1.0
        
        if viewRatio > bufferRatio {
            // Screen is taller than buffer (most iPhones)
            // Height matches, X is center-cropped.
            scale = viewSize.height
            let virtualWidth = scale / bufferRatio
            xOffset = (virtualWidth - viewSize.width) / 2.0
            
            // For front camera (mirrored):
            // Vision x=0 is right, x=1 is left.
            // We want screen x=0 on left, x=width on right.
            return CGPoint(
                x: (1.0 - point.x) * virtualWidth - xOffset,
                y: (1.0 - point.y) * viewSize.height
            )
        } else {
            // Screen is wider than buffer (iPad / Landscape)
            // Width matches, Y is center-cropped.
            scale = viewSize.width
            let virtualHeight = scale * bufferRatio
            yOffset = (virtualHeight - viewSize.height) / 2.0
            
            return CGPoint(
                x: (1.0 - point.x) * viewSize.width,
                y: (1.0 - point.y) * virtualHeight - yOffset
            )
        }
    }
}

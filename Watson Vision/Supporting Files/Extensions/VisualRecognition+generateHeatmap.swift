//
//  Heatmap.swift
//  Core ML Vision
//
//  Created by Nicholas Bourdakos on 3/7/19.
//

import UIKit
import VisualRecognitionV3

extension UIImage {
    func mask(at point: CGPoint) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(self.size, false, UIScreen.main.scale)
        
        self.draw(at: .zero)
        
        let rectangle = CGRect(x: point.x * 16, y: point.y * 16, width: 64, height: 64)
        
        UIColor(red: 1, green: 0, blue: 1, alpha: 1).setFill()
        UIRectFill(rectangle)
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return newImage
    }
}

extension VisualRecognition {
    private struct Point: Hashable {
        var x: Int
        var y: Int
        var cgPoint: CGPoint {
            return CGPoint(x: x, y: y)
        }
    }
    
    private struct OutlineState {
        var position: Point = Point(x: 0, y: 0)
        var path: UIBezierPath = UIBezierPath()
        var pathStart: CGPoint = CGPoint(x: -1, y: -1)
        var velocity: Direction = .right
        var check: Direction = .up
        var seen: Set<Point> = Set<Point>()
    }
    
    private enum Direction: String {
        case up, right, down, left
    }
    
    private func renderOutline(_ heatmap: [[CGFloat]], size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, UIScreen.main.scale)
        
        let scale = size.width / 14
        let offset = (size.height - size.width) / 2
        
        var seen = Set<Point>()
        
        for (down, row) in heatmap.enumerated() {
            for (right, mean) in row.enumerated() {
                if !seen.contains(Point(x: right, y: down)) && mean <= 0.5 {
                    
                    // If the block is surrounded by blocks, break.
                    if (down <= 0 || heatmap[down - 1][right] <= 0.5)
                        && (right >= heatmap[down].count - 1 || heatmap[down][right + 1] <= 0.5)
                        && (down >= heatmap.count - 1 || heatmap[down + 1][right] <= 0.5)
                        && (right <= 0 || heatmap[down][right - 1] <= 0.5) {
                        break
                    }
                    var state = OutlineState()
                    state.seen = seen
                    state.position = Point(x: right, y: down)
                    moveToBlock(heatmap, &state, scale: scale, offset: offset)
                    seen = state.seen
                    
                    print("CLOSING PATH")
                    state.path.close()
                    
                    state.path.lineWidth = 8
                    UIColor(red: 0 / 255, green: 0 / 255, blue: 0 / 255, alpha: 0.4).setStroke()
                    state.path.stroke()
                    
                    state.path.lineWidth = 6
                    UIColor(red: 255 / 255, green: 255 / 255, blue: 255 / 255, alpha: 1).setStroke()
                    state.path.stroke()
                }
            }
        }
        
        let outlinedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return outlinedImage
    }
    
    private func moveToBlock(_ heatmap: [[CGFloat]], _ state: inout OutlineState, scale: CGFloat, offset: CGFloat) {
        state.seen.insert(Point(x: state.position.x, y: state.position.y))
        
        print("moving \(state.velocity.rawValue.uppercased()) to (\(state.position.x + 1), \(state.position.y + 1))")
        
        // The direction is shifted by one, because we start out by rotating one when checking a line
        switch state.velocity {
        case .up:
            state.check = .down
            check(heatmap, &state, scale: scale, offset: offset)
            return
        case .right:
            state.check = .left
            check(heatmap, &state, scale: scale, offset: offset)
            return
        case .down:
            state.check = .up
            check(heatmap, &state, scale: scale, offset: offset)
            return
        case .left:
            state.check = .right
            check(heatmap, &state, scale: scale, offset: offset)
            return
        }
    }
    
    private func check(_ heatmap: [[CGFloat]], _ state: inout OutlineState, scale: CGFloat, offset: CGFloat) {
        setNextCheck(&state)
        
        if needsEdge(heatmap, &state) {
            drawEdge(&state, scale: scale, offset: offset)
            
            if state.path.currentPoint == state.pathStart {
                return
            }
            
            print("draw \(state.check.rawValue.uppercased()) edge")
            check(heatmap, &state, scale: scale, offset: offset)
            return
        } else {
            state.velocity = state.check
            setMove(&state)
            moveToBlock(heatmap, &state, scale: scale, offset: offset)
            return
        }
    }
    
    private func needsEdge(_ heatmap: [[CGFloat]], _ state: inout OutlineState) -> Bool {
        let down = state.position.y
        let right = state.position.x
        
        switch state.check {
        case .up:
            return down <= 0 || heatmap[down - 1][right] > 0.5
        case .right:
            return right >= heatmap[down].count - 1 || heatmap[down][right + 1] > 0.5
        case .down:
            return down >= heatmap.count - 1 || heatmap[down + 1][right] > 0.5
        case .left:
            return right <= 0 || heatmap[down][right - 1] > 0.5
        }
    }
    
    private func setNextCheck(_ state: inout OutlineState) {
        switch state.check {
        case .up:
            state.check = .right
        case .right:
            state.check = .down
        case .down:
            state.check = .left
        case .left:
            state.check = .up
        }
    }
    
    private func setMove(_ state: inout OutlineState) {
        switch state.velocity {
        case .up:
            state.position.y = state.position.y - 1
        case .right:
            state.position.x = state.position.x + 1
        case .down:
            state.position.y = state.position.y + 1
        case .left:
            state.position.x = state.position.x - 1
        }
    }
    
    private func drawEdge(_ state: inout OutlineState, scale: CGFloat, offset: CGFloat) {
        let down = state.position.cgPoint.y
        let right = state.position.cgPoint.x
        
        let topLeft = CGPoint(x: right * scale, y: down * scale + offset)
        let topRight = CGPoint(x: right * scale + scale, y: down * scale + offset)
        let bottomRight = CGPoint(x: right * scale + scale, y: down * scale + scale + offset)
        let bottomLeft = CGPoint(x: right * scale, y: down * scale + scale + offset)
        
        switch state.check {
        case .up:
            if state.pathStart == CGPoint(x: -1, y: -1) {
                print("JUMP")
                state.path.move(to: topLeft)
                state.pathStart = topLeft
            }
            state.path.addLine(to: topRight)
        case .right:
            if state.pathStart == CGPoint(x: -1, y: -1) {
                print("JUMP")
                state.path.move(to: topRight)
                state.pathStart = topRight
            }
            state.path.addLine(to: bottomRight)
        case .down:
            if state.pathStart == CGPoint(x: -1, y: -1) {
                print("JUMP")
                state.path.move(to: bottomRight)
                state.pathStart = bottomRight
            }
            state.path.addLine(to: bottomLeft)
        case .left:
            if state.pathStart == CGPoint(x: -1, y: -1) {
                print("JUMP")
                state.path.move(to: bottomLeft)
                state.pathStart = bottomLeft
            }
            state.path.addLine(to: topLeft)
        }
    }
    
    private func calculateHeatmap(_ confidences: [[Double]], _ originalConf: Double) -> [[CGFloat]] {
        var minVal: CGFloat = 1.0
        
        var heatmap = [[CGFloat]](repeating: [CGFloat](repeating: -1, count: 14), count: 14)
        
        // loop through each confidence
        for down in 0 ..< 14 {
            for right in 0 ..< 14 {
                // A 4x4 slice of the confidences
                let kernel = confidences[down + 0...down + 3].map({ $0[right + 0...right + 3] })
                
                // loop through each confidence in the slice and get the average, ignoring -1
                var result = 0.0
                let weights = [
                    [0.1, 0.5, 0.5, 0.1],
                    [0.5, 1.0, 1.0, 0.5],
                    [0.5, 1.0, 1.0, 0.5],
                    [0.1, 0.5, 0.5, 0.1],
                    ]
                var count = weights.joined().reduce(0, +)
                for (down, row) in kernel.enumerated() {
                    for (right, score) in row.enumerated() {
                        if score == -1 {
                            count -= weights[down][right]
                        } else {
                            result += score * weights[down][right]
                        }
                    }
                }
                
                let mean = CGFloat(result / count)
                
                heatmap[down][right] = mean
                
                minVal = min(mean, minVal)
            }
        }
        
        for (down, row) in heatmap.enumerated() {
            for (right, mean) in row.enumerated() {
                let newalpha = 1 - max(CGFloat(originalConf) - mean, 0) / max(CGFloat(originalConf) - minVal, 0)
                let cappedAlpha = min(max(newalpha, 0), 1)
                heatmap[down][right] = cappedAlpha
            }
        }
        
        return heatmap
    }
    
    private func renderHeatmap(_ heatmap: [[CGFloat]], color: UIColor, size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, UIScreen.main.scale)
        
        let scale = size.width / 14
        let offset = (size.height - size.width) / 2
        
        for (down, row) in heatmap.enumerated() {
            for (right, mean) in row.enumerated() {
                let rectangle = CGRect(x: CGFloat(right) * scale, y: CGFloat(down) * scale + offset, width: scale, height: scale)
                color.withAlphaComponent(mean).setFill()
                UIRectFillUsingBlendMode(rectangle, .normal)
            }
        }
        
        color.setFill()
        
        let topMargin = CGRect(x: 0, y: 0, width: size.width, height: offset)
        let bottomMargin = CGRect(x: 0, y: size.width + offset, width: size.width, height: offset)
        UIRectFillUsingBlendMode(topMargin, .normal)
        UIRectFillUsingBlendMode(bottomMargin, .normal)
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return newImage
    }
    
    struct Heatmap {
        let heatmap: UIImage
        let outline: UIImage
    }
    
    func generateHeatmap(image: UIImage, classifierId: String, className: String, localThreshold: Double = 0.0, completionHandler: @escaping (Heatmap) -> Void) {
        guard let croppedImage = image.cropToCenter(targetSize: CGSize(width: 224, height: 224)) else {
            return
        }
        
        var confidences = [[Double]](repeating: [Double](repeating: -1, count: 17), count: 17)
        
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        
        DispatchQueue.global(qos: .background).async {
            for down in 0 ..< 11 {
                for right in 0 ..< 11 {
                    confidences[down + 3][right + 3] = 0
                    dispatchGroup.enter()
                    let maskedImage = croppedImage.mask(at: CGPoint(x: right, y: down))
                    self.classifyWithLocalModel(image: maskedImage, classifierIDs: [classifierId], threshold: localThreshold) { [down, right] classifiedImages, _ in
                        
                        defer { dispatchGroup.leave() }
                        
                        // Make sure that an image was successfully classified.
                        guard let classifications = classifiedImages?.images.first?.classifiers.first?.classes, let classResult = classifications.first(where: { $0.className == className }) else {
                            return
                        }
                        
                        confidences[down + 3][right + 3] = classResult.score
                        print(".", terminator: "")
                    }
                }
            }
            dispatchGroup.leave()
            
            dispatchGroup.notify(queue: .main) {
                print("\n\(confidences)")
                
                self.classifyWithLocalModel(image: croppedImage, classifierIDs: [classifierId], threshold: localThreshold) { classifiedImages, error in
                    // Make sure that an image was successfully classified.
                    guard let classifications = classifiedImages?.images.first?.classifiers.first?.classes, let classResult = classifications.first(where: { $0.className == className }) else {
                        return
                    }
                    
                    let heatmapScores = self.calculateHeatmap(confidences, classResult.score)
                    let heatmapImage = self.renderHeatmap(heatmapScores, color: .black, size: image.size)
                    let outlineImage = self.renderOutline(heatmapScores, size: image.size)
                    
                    let heatmap = Heatmap(heatmap: heatmapImage, outline: outlineImage)
                    completionHandler(heatmap)
                }
            }
        }
    }
}

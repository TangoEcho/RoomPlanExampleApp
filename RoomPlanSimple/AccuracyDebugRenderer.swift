import UIKit
import simd
import RoomPlan

/// AccuracyDebugRenderer provides side-by-side visualization comparing 3D RoomPlan data
/// with the 2D floor plan rendering to help debug accuracy issues.
class AccuracyDebugRenderer: UIView {
    
    // MARK: - Properties
    
    private var validationResults: RoomAccuracyValidator.ValidationResults?
    private var debugData: DebugVisualizationData?
    private var showAccuracyHeatmap = true
    private var showMismatchHighlights = true
    
    // Layout properties
    private let sideBySideMode = true
    private let leftPanelTitle = "3D RoomPlan Data"
    private let rightPanelTitle = "2D Floor Plan Rendering"
    
    // Drawing properties
    private let headerHeight: CGFloat = 40
    private let dividerWidth: CGFloat = 2
    private let padding: CGFloat = 20
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = UIColor.systemGray6
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = UIColor.systemGray4.cgColor
    }
    
    // MARK: - Public Methods
    
    func updateWithValidationResults(_ results: RoomAccuracyValidator.ValidationResults) {
        self.validationResults = results
        self.debugData = RoomAccuracyValidator().generateDebugVisualizationData()
        setNeedsDisplay()
        
        print("🎨 AccuracyDebugRenderer: Updated with validation results")
        print("   Overall accuracy: \(String(format: "%.1f", results.overallAccuracyScore * 100))%")
    }
    
    func setShowAccuracyHeatmap(_ show: Bool) {
        self.showAccuracyHeatmap = show
        setNeedsDisplay()
    }
    
    func setShowMismatchHighlights(_ show: Bool) {
        self.showMismatchHighlights = show
        setNeedsDisplay()
    }
    
    // MARK: - Drawing
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        guard let context = UIGraphicsGetCurrentContext() else { return }
        guard let results = validationResults else {
            drawEmptyState(in: context, rect: rect)
            return
        }
        
        print("🎨 AccuracyDebugRenderer: Drawing accuracy comparison")
        
        // Clear background
        context.clear(rect)
        if let bgColor = backgroundColor {
            context.setFillColor(bgColor.cgColor)
            context.fill(rect)
        }
        
        // Draw headers
        drawHeaders(in: context, rect: rect)
        
        // Calculate panel areas
        let panelRect = calculatePanelRect(from: rect)
        let leftPanel = CGRect(x: panelRect.minX, y: panelRect.minY, 
                              width: panelRect.width / 2 - dividerWidth / 2, height: panelRect.height)
        let rightPanel = CGRect(x: panelRect.midX + dividerWidth / 2, y: panelRect.minY, 
                               width: panelRect.width / 2 - dividerWidth / 2, height: panelRect.height)
        
        // Draw divider
        drawDivider(in: context, rect: panelRect)
        
        // Draw 3D data visualization (left panel)
        draw3DDataVisualization(in: context, rect: leftPanel, results: results)
        
        // Draw 2D data visualization (right panel)
        draw2DDataVisualization(in: context, rect: rightPanel, results: results)
        
        // Draw accuracy overlays
        if showAccuracyHeatmap {
            drawAccuracyHeatmap(in: context, leftRect: leftPanel, rightRect: rightPanel, results: results)
        }
        
        if showMismatchHighlights {
            drawMismatchHighlights(in: context, leftRect: leftPanel, rightRect: rightPanel, results: results)
        }
        
        // Draw accuracy metrics
        drawAccuracyMetrics(in: context, rect: rect, results: results)
    }
    
    private func drawEmptyState(in context: CGContext, rect: CGRect) {
        let message = "No validation data available.\nRun room accuracy validation to see comparison."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel,
            .paragraphStyle: NSMutableParagraphStyle()
        ]
        
        let style = attributes[.paragraphStyle] as! NSMutableParagraphStyle
        style.alignment = .center
        style.lineSpacing = 4
        
        let attributedText = NSAttributedString(string: message, attributes: attributes)
        let textSize = attributedText.boundingRect(
            with: rect.size,
            options: [.usesLineFragmentOrigin],
            context: nil
        ).size
        
        let textRect = CGRect(
            x: (rect.width - textSize.width) / 2,
            y: (rect.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        attributedText.draw(in: textRect)
    }
    
    private func drawHeaders(in context: CGContext, rect: CGRect) {
        let headerRect = CGRect(x: 0, y: 0, width: rect.width, height: headerHeight)
        
        // Draw main title
        let mainTitle = "Room Accuracy Debug Comparison"
        drawText(mainTitle, in: context, rect: headerRect, 
                font: .boldSystemFont(ofSize: 18), color: .label, alignment: .center)
        
        if sideBySideMode {
            let leftHeaderRect = CGRect(x: padding, y: headerHeight + 5, 
                                      width: rect.width / 2 - padding - dividerWidth / 2, height: 25)
            let rightHeaderRect = CGRect(x: rect.width / 2 + dividerWidth / 2, y: headerHeight + 5, 
                                       width: rect.width / 2 - padding - dividerWidth / 2, height: 25)
            
            drawText(leftPanelTitle, in: context, rect: leftHeaderRect,
                    font: .systemFont(ofSize: 14, weight: .medium), color: .secondaryLabel, alignment: .center)
            drawText(rightPanelTitle, in: context, rect: rightHeaderRect,
                    font: .systemFont(ofSize: 14, weight: .medium), color: .secondaryLabel, alignment: .center)
        }
    }
    
    private func calculatePanelRect(from rect: CGRect) -> CGRect {
        let topOffset = headerHeight + 35 // Account for main title and subtitle
        return CGRect(x: padding, y: topOffset, 
                     width: rect.width - padding * 2, 
                     height: rect.height - topOffset - 80) // Reserve space for metrics at bottom
    }
    
    private func drawDivider(in context: CGContext, rect: CGRect) {
        let dividerRect = CGRect(x: rect.midX - dividerWidth / 2, y: rect.minY, 
                                width: dividerWidth, height: rect.height)
        
        context.setFillColor(UIColor.separator.cgColor)
        context.fill(dividerRect)
    }
    
    private func draw3DDataVisualization(in context: CGContext, rect: CGRect, results: RoomAccuracyValidator.ValidationResults) {
        print("🎨 Drawing 3D data visualization in rect: \(rect)")
        
        // Draw background
        context.setFillColor(UIColor.systemBackground.cgColor)
        context.fill(rect.insetBy(dx: 2, dy: 2))
        
        context.setStrokeColor(UIColor.systemGray4.cgColor)
        context.setLineWidth(1)
        context.stroke(rect.insetBy(dx: 2, dy: 2))
        
        // Calculate coordinate transform for 3D data
        let transform = calculate3DCoordinateTransform(for: results.extractedRoomData, in: rect)
        
        // Draw 3D walls
        draw3DWalls(in: context, rect: rect, walls: results.extractedRoomData.wallPositions, transform: transform)
        
        // Draw 3D furniture
        draw3DFurniture(in: context, rect: rect, furniture: results.extractedRoomData.furniturePositions, transform: transform)
        
        // Draw room bounds
        draw3DRoomBounds(in: context, rect: rect, bounds: results.extractedRoomData.roomBounds, transform: transform)
        
        // Add accuracy indicators
        drawAccuracyIndicators3D(in: context, rect: rect, results: results, transform: transform)
    }
    
    private func draw2DDataVisualization(in context: CGContext, rect: CGRect, results: RoomAccuracyValidator.ValidationResults) {
        print("🎨 Drawing 2D data visualization in rect: \(rect)")
        
        // Draw background
        context.setFillColor(UIColor.systemBackground.cgColor)
        context.fill(rect.insetBy(dx: 2, dy: 2))
        
        context.setStrokeColor(UIColor.systemGray4.cgColor)
        context.setLineWidth(1)
        context.stroke(rect.insetBy(dx: 2, dy: 2))
        
        // Calculate coordinate transform for 2D data
        let transform = calculate2DCoordinateTransform(for: results.floorPlanData, in: rect)
        
        // Draw 2D wall points
        draw2DWalls(in: context, rect: rect, wallPoints: results.floorPlanData.renderedWallPoints, transform: transform)
        
        // Draw 2D furniture
        draw2DFurniture(in: context, rect: rect, furniturePositions: results.floorPlanData.renderedFurniturePositions, transform: transform)
        
        // Draw room bounds
        draw2DRoomBounds(in: context, rect: rect, bounds: results.floorPlanData.renderedRoomBounds, transform: transform)
        
        // Add accuracy indicators
        drawAccuracyIndicators2D(in: context, rect: rect, results: results, transform: transform)
    }
    
    // MARK: - 3D Visualization Methods
    
    private func calculate3DCoordinateTransform(for data: RoomAccuracyValidator.ExtractedRoomData, in rect: CGRect) -> CoordinateTransform3D {
        let bounds = data.roomBounds
        let size3D = bounds.max - bounds.min
        
        let availableSize = CGSize(width: rect.width - 20, height: rect.height - 20)
        let scaleX = size3D.x > 0 ? Float(availableSize.width) / size3D.x : 1.0
        let scaleZ = size3D.z > 0 ? Float(availableSize.height) / size3D.z : 1.0
        let scale = min(scaleX, scaleZ)
        
        let center3D = bounds.center
        let viewCenter = CGPoint(x: rect.midX, y: rect.midY)
        
        return CoordinateTransform3D(
            scale: scale,
            offsetX: Float(viewCenter.x) - center3D.x * scale,
            offsetY: Float(viewCenter.y) - center3D.z * scale
        )
    }
    
    private func draw3DWalls(in context: CGContext, rect: CGRect, walls: [RoomAccuracyValidator.WallData], transform: CoordinateTransform3D) {
        for (index, wall) in walls.enumerated() {
            let viewPoint = transform3DToView(wall.position, transform: transform)
            
            // Draw wall as rectangle representing its dimensions
            let wallWidth = CGFloat(wall.dimensions.x * transform.scale)
            let wallHeight = CGFloat(wall.dimensions.z * transform.scale)
            
            let wallRect = CGRect(x: viewPoint.x - wallWidth/2, y: viewPoint.y - wallHeight/2,
                                 width: wallWidth, height: wallHeight)
            
            // Color based on confidence
            let color = colorForConfidence(wall.confidence)
            context.setFillColor(color.withAlphaComponent(0.3).cgColor)
            context.fill(wallRect)
            
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(2)
            context.stroke(wallRect)
            
            // Draw wall number
            drawText("\(index + 1)", in: context, rect: CGRect(x: viewPoint.x - 10, y: viewPoint.y - 10, width: 20, height: 20),
                    font: .boldSystemFont(ofSize: 12), color: color, alignment: .center)
        }
    }
    
    private func draw3DFurniture(in context: CGContext, rect: CGRect, furniture: [RoomAccuracyValidator.FurnitureData], transform: CoordinateTransform3D) {
        for (index, item) in furniture.enumerated() {
            let viewPoint = transform3DToView(item.position, transform: transform)
            
            let furnitureWidth = CGFloat(max(item.dimensions.x, 0.3) * transform.scale)
            let furnitureHeight = CGFloat(max(item.dimensions.z, 0.3) * transform.scale)
            
            let furnitureRect = CGRect(x: viewPoint.x - furnitureWidth/2, y: viewPoint.y - furnitureHeight/2,
                                     width: furnitureWidth, height: furnitureHeight)
            
            // Color based on category
            let color = colorForFurnitureCategory(item.category)
            
            // Draw as oval for round furniture, rectangle for others
            let isRoundFurniture = [.table, .chair].contains(item.category)
            
            if isRoundFurniture {
                context.setFillColor(color.withAlphaComponent(0.6).cgColor)
                context.fillEllipse(in: furnitureRect)
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(1.5)
                context.strokeEllipse(in: furnitureRect)
            } else {
                context.setFillColor(color.withAlphaComponent(0.6).cgColor)
                context.fill(furnitureRect)
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(1.5)
                context.stroke(furnitureRect)
            }
            
            // Add emoji label if there's space
            if furnitureWidth > 20 && furnitureHeight > 15 {
                let emoji = emojiForFurnitureCategory(item.category)
                drawText(emoji, in: context, rect: CGRect(x: viewPoint.x - 10, y: viewPoint.y - 10, width: 20, height: 20),
                        font: .systemFont(ofSize: 12), color: .label, alignment: .center)
            }
        }
    }
    
    private func draw3DRoomBounds(in context: CGContext, rect: CGRect, bounds: RoomAccuracyValidator.RoomBounds, transform: CoordinateTransform3D) {
        let minPoint = transform3DToView(bounds.min, transform: transform)
        let maxPoint = transform3DToView(bounds.max, transform: transform)
        
        let boundsRect = CGRect(x: minPoint.x, y: minPoint.y,
                               width: maxPoint.x - minPoint.x,
                               height: maxPoint.y - minPoint.y)
        
        context.setStrokeColor(UIColor.systemRed.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(1)
        context.stroke(boundsRect)
        
        // Add dimensions label
        let width = bounds.max.x - bounds.min.x
        let depth = bounds.max.z - bounds.min.z
        let dimensionText = "\(String(format: "%.1f", width))m × \(String(format: "%.1f", depth))m"
        
        let labelRect = CGRect(x: boundsRect.minX, y: boundsRect.minY - 20, width: boundsRect.width, height: 15)
        drawText(dimensionText, in: context, rect: labelRect,
                font: .systemFont(ofSize: 10), color: .systemRed, alignment: .center)
    }
    
    private func drawAccuracyIndicators3D(in context: CGContext, rect: CGRect, results: RoomAccuracyValidator.ValidationResults, transform: CoordinateTransform3D) {
        // Draw accuracy indicators for walls and furniture
        
        // Highlight walls with high position errors
        for (index, wall) in results.extractedRoomData.wallPositions.enumerated() {
            if index < results.comparisonResults.wallAccuracy.positionErrors.count {
                let error = results.comparisonResults.wallAccuracy.positionErrors[index]
                if error > 0.5 { // Significant error
                    let viewPoint = transform3DToView(wall.position, transform: transform)
                    
                    // Draw error indicator
                    let errorRadius: CGFloat = 8
                    let errorRect = CGRect(x: viewPoint.x - errorRadius, y: viewPoint.y - errorRadius,
                                         width: errorRadius * 2, height: errorRadius * 2)
                    
                    let errorColor = error > 1.0 ? UIColor.systemRed : UIColor.systemOrange
                    context.setFillColor(errorColor.withAlphaComponent(0.7).cgColor)
                    context.fillEllipse(in: errorRect)
                    
                    context.setStrokeColor(errorColor.cgColor)
                    context.setLineWidth(2)
                    context.strokeEllipse(in: errorRect)
                    
                    // Add error value
                    let errorText = String(format: "%.1fm", error)
                    drawText(errorText, in: context, rect: CGRect(x: viewPoint.x - 15, y: viewPoint.y + 15, width: 30, height: 12),
                            font: .boldSystemFont(ofSize: 9), color: errorColor, alignment: .center)
                }
            }
        }
    }
    
    // MARK: - 2D Visualization Methods
    
    private func calculate2DCoordinateTransform(for data: RoomAccuracyValidator.FloorPlanData, in rect: CGRect) -> CoordinateTransform2D {
        let bounds = data.renderedRoomBounds
        let size2D = bounds.max - bounds.min
        
        let availableSize = CGSize(width: rect.width - 20, height: rect.height - 20)
        let scaleX = size2D.x > 0 ? Float(availableSize.width) / size2D.x : 1.0
        let scaleY = size2D.y > 0 ? Float(availableSize.height) / size2D.y : 1.0
        let scale = min(scaleX, scaleY)
        
        let center2D = bounds.center
        let viewCenter = CGPoint(x: rect.midX, y: rect.midY)
        
        return CoordinateTransform2D(
            scale: scale,
            offsetX: Float(viewCenter.x) - center2D.x * scale,
            offsetY: Float(viewCenter.y) - center2D.y * scale
        )
    }
    
    private func draw2DWalls(in context: CGContext, rect: CGRect, wallPoints: [simd_float2], transform: CoordinateTransform2D) {
        guard !wallPoints.isEmpty else { return }
        
        // Draw wall points as connected polygon
        let viewPoints = wallPoints.map { point in
            transform2DToView(point, transform: transform)
        }
        
        if viewPoints.count >= 3 {
            let path = CGMutablePath()
            path.move(to: viewPoints[0])
            
            for i in 1..<viewPoints.count {
                path.addLine(to: viewPoints[i])
            }
            path.closeSubpath()
            
            context.setFillColor(UIColor.systemBlue.withAlphaComponent(0.1).cgColor)
            context.addPath(path)
            context.fillPath()
            
            context.setStrokeColor(UIColor.systemBlue.cgColor)
            context.setLineWidth(2)
            context.addPath(path)
            context.strokePath()
        }
        
        // Draw individual wall points
        for (index, point) in viewPoints.enumerated() {
            let pointRect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            context.setFillColor(UIColor.systemBlue.cgColor)
            context.fillEllipse(in: pointRect)
            
            // Add point number
            drawText("\(index + 1)", in: context, rect: CGRect(x: point.x - 8, y: point.y + 8, width: 16, height: 12),
                    font: .boldSystemFont(ofSize: 10), color: .systemBlue, alignment: .center)
        }
    }
    
    private func draw2DFurniture(in context: CGContext, rect: CGRect, furniturePositions: [simd_float2], transform: CoordinateTransform2D) {
        for (index, position) in furniturePositions.enumerated() {
            let viewPoint = transform2DToView(position, transform: transform)
            
            let furnitureSize: CGFloat = 12
            let furnitureRect = CGRect(x: viewPoint.x - furnitureSize/2, y: viewPoint.y - furnitureSize/2,
                                     width: furnitureSize, height: furnitureSize)
            
            context.setFillColor(UIColor.systemGreen.withAlphaComponent(0.6).cgColor)
            context.fillEllipse(in: furnitureRect)
            context.setStrokeColor(UIColor.systemGreen.cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: furnitureRect)
            
            // Add furniture number
            drawText("\(index + 1)", in: context, rect: CGRect(x: viewPoint.x - 8, y: viewPoint.y + 8, width: 16, height: 12),
                    font: .boldSystemFont(ofSize: 10), color: .systemGreen, alignment: .center)
        }
    }
    
    private func draw2DRoomBounds(in context: CGContext, rect: CGRect, bounds: RoomAccuracyValidator.RoomBounds2D, transform: CoordinateTransform2D) {
        let minPoint = transform2DToView(bounds.min, transform: transform)
        let maxPoint = transform2DToView(bounds.max, transform: transform)
        
        let boundsRect = CGRect(x: minPoint.x, y: minPoint.y,
                               width: maxPoint.x - minPoint.x,
                               height: maxPoint.y - minPoint.y)
        
        context.setStrokeColor(UIColor.systemPurple.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(1)
        context.stroke(boundsRect)
        
        // Add dimensions label
        let width = bounds.max.x - bounds.min.x
        let height = bounds.max.y - bounds.min.y
        let dimensionText = "\(String(format: "%.1f", width)) × \(String(format: "%.1f", height))"
        
        let labelRect = CGRect(x: boundsRect.minX, y: boundsRect.minY - 20, width: boundsRect.width, height: 15)
        drawText(dimensionText, in: context, rect: labelRect,
                font: .systemFont(ofSize: 10), color: .systemPurple, alignment: .center)
    }
    
    private func drawAccuracyIndicators2D(in context: CGContext, rect: CGRect, results: RoomAccuracyValidator.ValidationResults, transform: CoordinateTransform2D) {
        // Highlight furniture with high position errors
        for (index, position) in results.floorPlanData.renderedFurniturePositions.enumerated() {
            if index < results.comparisonResults.furnitureAccuracy.positionErrors.count {
                let error = results.comparisonResults.furnitureAccuracy.positionErrors[index]
                if error > 0.3 { // Significant error for furniture
                    let viewPoint = transform2DToView(position, transform: transform)
                    
                    // Draw error indicator
                    let errorRadius: CGFloat = 6
                    let errorRect = CGRect(x: viewPoint.x - errorRadius, y: viewPoint.y - errorRadius,
                                         width: errorRadius * 2, height: errorRadius * 2)
                    
                    let errorColor = error > 0.5 ? UIColor.systemRed : UIColor.systemOrange
                    context.setFillColor(errorColor.withAlphaComponent(0.7).cgColor)
                    context.fillEllipse(in: errorRect)
                    
                    context.setStrokeColor(errorColor.cgColor)
                    context.setLineWidth(2)
                    context.strokeEllipse(in: errorRect)
                }
            }
        }
    }
    
    // MARK: - Accuracy Overlays
    
    private func drawAccuracyHeatmap(in context: CGContext, leftRect: CGRect, rightRect: CGRect, results: RoomAccuracyValidator.ValidationResults) {
        // Draw semi-transparent heatmap overlay showing accuracy levels
        
        // Create gradient for accuracy visualization
        let colors = [
            UIColor.systemRed.withAlphaComponent(0.3).cgColor,      // Poor accuracy
            UIColor.systemOrange.withAlphaComponent(0.3).cgColor,   // Medium accuracy
            UIColor.systemYellow.withAlphaComponent(0.3).cgColor,   // Good accuracy
            UIColor.systemGreen.withAlphaComponent(0.3).cgColor     // Excellent accuracy
        ]
        
        let locations: [CGFloat] = [0.0, 0.33, 0.66, 1.0]
        
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations) {
            // Draw accuracy gradient overlay
            let overlayAlpha: CGFloat = 0.2
            
            // Left panel accuracy overlay
            context.saveGState()
            context.clip(to: leftRect)
            context.drawLinearGradient(gradient, start: CGPoint(x: leftRect.minX, y: leftRect.minY),
                                     end: CGPoint(x: leftRect.maxX, y: leftRect.maxY), options: [])
            context.restoreGState()
            
            // Right panel accuracy overlay
            context.saveGState()
            context.clip(to: rightRect)
            context.drawLinearGradient(gradient, start: CGPoint(x: rightRect.minX, y: rightRect.minY),
                                     end: CGPoint(x: rightRect.maxX, y: rightRect.maxY), options: [])
            context.restoreGState()
        }
    }
    
    private func drawMismatchHighlights(in context: CGContext, leftRect: CGRect, rightRect: CGRect, results: RoomAccuracyValidator.ValidationResults) {
        // Highlight mismatched elements with connecting lines
        
        let transform3D = calculate3DCoordinateTransform(for: results.extractedRoomData, in: leftRect)
        let transform2D = calculate2DCoordinateTransform(for: results.floorPlanData, in: rightRect)
        
        // Draw lines connecting mismatched furniture
        context.setStrokeColor(UIColor.systemRed.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [4, 2])
        
        let furniture3D = results.extractedRoomData.furniturePositions
        let furniture2D = results.floorPlanData.renderedFurniturePositions
        
        for (index, furniture) in furniture3D.enumerated() {
            if index < furniture2D.count {
                let point3D = transform3DToView(furniture.position, transform: transform3D)
                let point2D = transform2DToView(furniture2D[index], transform: transform2D)
                
                // Adjust points to be relative to their respective panels
                let adjustedPoint3D = CGPoint(x: point3D.x, y: point3D.y)
                let adjustedPoint2D = CGPoint(x: point2D.x, y: point2D.y)
                
                context.move(to: adjustedPoint3D)
                context.addLine(to: adjustedPoint2D)
                context.strokePath()
            }
        }
        
        context.setLineDash(phase: 0, lengths: [])
    }
    
    private func drawAccuracyMetrics(in context: CGContext, rect: CGRect, results: RoomAccuracyValidator.ValidationResults) {
        // Draw accuracy metrics at the bottom
        let metricsRect = CGRect(x: padding, y: rect.height - 75, width: rect.width - padding * 2, height: 70)
        
        // Background for metrics
        context.setFillColor(UIColor.secondarySystemBackground.cgColor)
        let metricsBackground = metricsRect.insetBy(dx: -5, dy: -5)
        let metricsPath = UIBezierPath(roundedRect: metricsBackground, cornerRadius: 8)
        context.addPath(metricsPath.cgPath)
        context.fillPath()
        
        // Metrics text
        let overallAccuracy = results.overallAccuracyScore * 100
        let wallAccuracy = results.comparisonResults.wallAccuracy.wallMatchingRate * 100
        let furnitureAccuracy = results.comparisonResults.furnitureAccuracy.furnitureMatchingRate * 100
        
        let metricsText = """
        Overall Accuracy: \(String(format: "%.1f", overallAccuracy))% | Wall Matching: \(String(format: "%.1f", wallAccuracy))% | Furniture Matching: \(String(format: "%.1f", furnitureAccuracy))%
        Avg Wall Error: \(String(format: "%.2f", results.comparisonResults.wallAccuracy.averagePositionError))m | Avg Furniture Error: \(String(format: "%.2f", results.comparisonResults.furnitureAccuracy.averagePositionError))m
        """
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.label,
            .paragraphStyle: {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                style.lineSpacing = 2
                return style
            }()
        ]
        
        let attributedText = NSAttributedString(string: metricsText, attributes: attributes)
        attributedText.draw(in: metricsRect)
    }
    
    // MARK: - Helper Methods
    
    private struct CoordinateTransform3D {
        let scale: Float
        let offsetX: Float
        let offsetY: Float
    }
    
    private struct CoordinateTransform2D {
        let scale: Float
        let offsetX: Float
        let offsetY: Float
    }
    
    private func transform3DToView(_ point3D: simd_float3, transform: CoordinateTransform3D) -> CGPoint {
        return CGPoint(
            x: CGFloat(point3D.x * transform.scale + transform.offsetX),
            y: CGFloat(point3D.z * transform.scale + transform.offsetY)
        )
    }
    
    private func transform2DToView(_ point2D: simd_float2, transform: CoordinateTransform2D) -> CGPoint {
        return CGPoint(
            x: CGFloat(point2D.x * transform.scale + transform.offsetX),
            y: CGFloat(point2D.y * transform.scale + transform.offsetY)
        )
    }
    
    private func colorForConfidence(_ confidence: Float) -> UIColor {
        switch confidence {
        case 0.8...1.0: return .systemGreen
        case 0.6..<0.8: return .systemYellow
        case 0.4..<0.6: return .systemOrange
        default: return .systemRed
        }
    }
    
    private func colorForFurnitureCategory(_ category: CapturedRoom.Object.Category) -> UIColor {
        switch category {
        case .table: return .systemBrown
        case .sofa: return .systemIndigo
        case .bed: return .systemPink
        case .storage: return .systemGreen
        case .chair: return .systemOrange
        default: return .systemGray2
        }
    }
    
    private func emojiForFurnitureCategory(_ category: CapturedRoom.Object.Category) -> String {
        switch category {
        case .table: return "📋"
        case .sofa: return "🛋️"
        case .bed: return "🛏️"
        case .storage: return "📦"
        case .chair: return "🪑"
        default: return "🔲"
        }
    }
    
    private func drawText(_ text: String, in context: CGContext, rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: {
                let style = NSMutableParagraphStyle()
                style.alignment = alignment
                return style
            }()
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        attributedString.draw(in: rect)
    }
}
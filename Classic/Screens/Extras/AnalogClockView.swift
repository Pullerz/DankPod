//
//  AnalogClockView.swift
//  Classic
//

import UIKit

/// A small glossy analog clock in the style of the 5G iPod's Clock extra.
/// The face (rim, dial, ticks, gloss) is drawn with Core Graphics; the hands are
/// shape layers rotated by transform, so ticking/sweeping is cheap and crisp at any size.
final class AnalogClockView: UIView {

    enum FaceStyle {
        case automatic      // day 6am–6pm in `timeZone`, night otherwise
        case day
        case night
        case placeholder    // dashed empty face ("New Clock")
    }

    var faceStyle: FaceStyle = .automatic { didSet { styleChanged() } }
    var timeZone: TimeZone = .current { didSet { update() } }
    var showsSecondHand: Bool = false { didSet { secondHand.isHidden = !showsSecondHand || isPlaceholder; applyHandColors() } }
    /// Minute ticks are drawn automatically on larger faces.
    var showsMinuteTicks: Bool { bounds.width >= 80 }

    private let hourHand = CAShapeLayer()
    private let minuteHand = CAShapeLayer()
    private let secondHand = CAShapeLayer()
    private let capLayer = CAShapeLayer()
    private var lastBuiltSize: CGSize = .zero
    private var isNight = false
    private var calendar = Calendar(identifier: .gregorian)

    private var isPlaceholder: Bool { faceStyle == .placeholder }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isUserInteractionEnabled = false
        for hand in [hourHand, minuteHand, secondHand, capLayer] {
            hand.contentsScale = UIScreen.main.scale
            layer.addSublayer(hand)
        }
        secondHand.isHidden = true
        styleChanged()
    }

    // MARK: Geometry

    /// Shadow margin around the clock so the drop shadow isn't clipped.
    private var margin: CGFloat { max(1.5, min(bounds.width, bounds.height) * 0.06) }
    private var outerRadius: CGFloat { min(bounds.width, bounds.height) / 2 - margin }
    private var rimWidth: CGFloat { max(1.5, outerRadius * 0.11) }
    private var faceRadius: CGFloat { outerRadius - rimWidth }
    private var pivot: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY - margin * 0.25) }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastBuiltSize {
            lastBuiltSize = bounds.size
            buildHands()
            setNeedsDisplay()
        }
        update()
    }

    private func buildHands() {
        let r = faceRadius
        guard r > 0 else { return }
        let c = pivot
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for hand in [hourHand, minuteHand, secondHand, capLayer] {
            hand.transform = CATransform3DIdentity
            hand.frame = bounds
            hand.anchorPoint = CGPoint(x: c.x / max(bounds.width, 1), y: c.y / max(bounds.height, 1))
            hand.frame = bounds
        }

        // Tapered hands pointing straight up from the pivot.
        func handPath(length: CGFloat, width: CGFloat, tail: CGFloat) -> CGPath {
            let p = UIBezierPath()
            p.move(to: CGPoint(x: c.x - width / 2, y: c.y + tail))
            p.addLine(to: CGPoint(x: c.x - width * 0.32, y: c.y - length))
            p.addArc(withCenter: CGPoint(x: c.x, y: c.y - length), radius: width * 0.32,
                     startAngle: .pi, endAngle: 0, clockwise: true)
            p.addLine(to: CGPoint(x: c.x + width / 2, y: c.y + tail))
            p.addArc(withCenter: CGPoint(x: c.x, y: c.y + tail), radius: width / 2,
                     startAngle: 0, endAngle: .pi, clockwise: true)
            p.close()
            return p.cgPath
        }
        hourHand.path = handPath(length: r * 0.52, width: max(2, r * 0.11), tail: r * 0.1)
        minuteHand.path = handPath(length: r * 0.80, width: max(1.5, r * 0.08), tail: r * 0.1)

        let sw = max(0.75, r * 0.022)
        let sp = UIBezierPath(rect: CGRect(x: c.x - sw / 2, y: c.y - r * 0.88, width: sw, height: r * 1.08))
        sp.append(UIBezierPath(ovalIn: CGRect(x: c.x - sw * 2.2, y: c.y + r * 0.12, width: sw * 4.4, height: sw * 4.4)))
        secondHand.path = sp.cgPath
        secondHand.fillColor = UIColor(red: 0.85, green: 0.1, blue: 0.08, alpha: 1).cgColor

        let capR = max(1.2, r * 0.07)
        capLayer.path = UIBezierPath(ovalIn: CGRect(x: c.x - capR, y: c.y - capR, width: capR * 2, height: capR * 2)).cgPath

        for hand in [hourHand, minuteHand, secondHand] {
            hand.shadowColor = UIColor.black.cgColor
            hand.shadowOpacity = r > 40 ? 0.35 : 0.2
            hand.shadowRadius = r > 40 ? 1.5 : 0.5
            hand.shadowOffset = CGSize(width: 0, height: r > 40 ? 1.5 : 0.5)
        }
        CATransaction.commit()
        applyHandColors()
    }

    // MARK: Style

    private func resolveNight(at date: Date) -> Bool {
        switch faceStyle {
        case .day, .placeholder: return false
        case .night: return true
        case .automatic: return !WorldClockStore.isDaytime(in: timeZone, at: date)
        }
    }

    private func styleChanged() {
        isNight = resolveNight(at: Date())
        let hidden = isPlaceholder
        hourHand.isHidden = hidden
        minuteHand.isHidden = hidden
        capLayer.isHidden = hidden
        secondHand.isHidden = hidden || !showsSecondHand
        applyHandColors()
        setNeedsDisplay()
        update()
    }

    private func applyHandColors() {
        let handColor = isNight ? UIColor.white : UIColor(white: 0.08, alpha: 1)
        hourHand.fillColor = handColor.cgColor
        minuteHand.fillColor = handColor.cgColor
        capLayer.fillColor = (showsSecondHand ? UIColor(red: 0.85, green: 0.1, blue: 0.08, alpha: 1) : handColor).cgColor
    }

    // MARK: Time

    /// Positions the hands for `date`. Call once a second (or per frame for a sweep).
    func update(to date: Date = Date()) {
        guard !isPlaceholder else { return }
        let night = resolveNight(at: date)
        if night != isNight {
            isNight = night
            applyHandColors()
            setNeedsDisplay()
        }
        calendar.timeZone = timeZone
        let comps = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let sec = Double(comps.second ?? 0) + Double(comps.nanosecond ?? 0) / 1_000_000_000
        let minute = Double(comps.minute ?? 0) + sec / 60
        let hour = Double((comps.hour ?? 0) % 12) + minute / 60

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hourHand.transform = CATransform3DMakeRotation(CGFloat(hour / 12 * 2 * .pi), 0, 0, 1)
        minuteHand.transform = CATransform3DMakeRotation(CGFloat(minute / 60 * 2 * .pi), 0, 0, 1)
        secondHand.transform = CATransform3DMakeRotation(CGFloat(sec / 60 * 2 * .pi), 0, 0, 1)
        CATransaction.commit()
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), outerRadius > 0 else { return }
        let c = pivot
        let R = outerRadius
        let r = faceRadius
        let space = CGColorSpaceCreateDeviceRGB()

        if isPlaceholder {
            let path = UIBezierPath(arcCenter: c, radius: R - 0.75, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
            path.lineWidth = max(1, R * 0.08)
            let dash = max(2, R * 0.28)
            path.setLineDash([dash, dash * 0.6], count: 2, phase: 0)
            UIColor(white: 0.55, alpha: 1).setStroke()
            path.stroke()
            return
        }

        let outer = CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2)

        // Drop shadow + metallic rim.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: max(0.5, R * 0.05)), blur: max(1, R * 0.12),
                      color: UIColor(white: 0, alpha: 0.45).cgColor)
        ctx.setFillColor(UIColor(white: 0.6, alpha: 1).cgColor)
        ctx.fillEllipse(in: outer)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addEllipse(in: outer)
        ctx.clip()
        let rimColors = isNight
            ? [UIColor(white: 0.62, alpha: 1), UIColor(white: 0.28, alpha: 1), UIColor(white: 0.12, alpha: 1)]
            : [UIColor(white: 0.97, alpha: 1), UIColor(white: 0.72, alpha: 1), UIColor(white: 0.5, alpha: 1)]
        if let g = CGGradient(colorsSpace: space, colors: rimColors.map { $0.cgColor } as CFArray, locations: [0, 0.55, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: c.x, y: outer.minY), end: CGPoint(x: c.x, y: outer.maxY), options: [])
        }
        ctx.restoreGState()

        // Dial.
        let face = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.saveGState()
        ctx.addEllipse(in: face)
        ctx.clip()
        let faceColors = isNight
            ? [UIColor(white: 0.2, alpha: 1), UIColor(white: 0.02, alpha: 1)]
            : [UIColor(white: 1, alpha: 1), UIColor(white: 0.88, alpha: 1)]
        if let g = CGGradient(colorsSpace: space, colors: faceColors.map { $0.cgColor } as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.x, y: c.y - r * 0.3), startRadius: 0,
                                   endCenter: c, endRadius: r * 1.05, options: [.drawsAfterEndLocation])
        }
        // Inner shadow from the rim.
        ctx.setShadow(offset: CGSize(width: 0, height: max(0.5, r * 0.04)), blur: max(1, r * 0.1),
                      color: UIColor(white: 0, alpha: isNight ? 0.8 : 0.35).cgColor)
        ctx.setStrokeColor(UIColor.black.cgColor)
        ctx.setLineWidth(r * 0.2)
        ctx.strokeEllipse(in: face.insetBy(dx: -r * 0.1, dy: -r * 0.1))
        ctx.restoreGState()

        // Ticks.
        let tickColor = isNight ? UIColor(white: 0.92, alpha: 1) : UIColor(white: 0.12, alpha: 1)
        ctx.setStrokeColor(tickColor.cgColor)
        ctx.setLineCap(.butt)
        let minorTicks = showsMinuteTicks
        for i in 0..<60 {
            let isHour = i % 5 == 0
            if !isHour && !minorTicks { continue }
            let isQuarter = i % 15 == 0
            let angle = CGFloat(i) / 60 * 2 * .pi
            let outerR = r * 0.92
            let len: CGFloat = isHour ? (isQuarter ? r * 0.2 : r * 0.14) : r * 0.06
            let width: CGFloat = isHour ? max(1, r * (isQuarter ? 0.05 : 0.035)) : max(0.5, r * 0.012)
            let s = sin(angle), co = cos(angle)
            ctx.setLineWidth(width)
            ctx.move(to: CGPoint(x: c.x + s * outerR, y: c.y - co * outerR))
            ctx.addLine(to: CGPoint(x: c.x + s * (outerR - len), y: c.y - co * (outerR - len)))
            ctx.strokePath()
        }

        // Glass gloss: a soft highlight over the upper half of the dial.
        ctx.saveGState()
        ctx.addEllipse(in: face)
        ctx.clip()
        let glossRect = CGRect(x: c.x - r * 0.85, y: c.y - r * 0.98, width: r * 1.7, height: r * 1.05)
        ctx.addEllipse(in: glossRect)
        ctx.clip()
        let glossColors = [UIColor(white: 1, alpha: isNight ? 0.22 : 0.55), UIColor(white: 1, alpha: 0)]
        if let g = CGGradient(colorsSpace: space, colors: glossColors.map { $0.cgColor } as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: c.x, y: glossRect.minY), end: CGPoint(x: c.x, y: glossRect.maxY), options: [])
        }
        ctx.restoreGState()
    }
}

//
//  HoldSwitchView.swift
//  Classic
//
//  The iPod's Hold slider, plus the padlock graphics shown while it's on.
//

import UIKit

// MARK: - Hold switch

/// A small metal slider. Sliding it right (or tapping it) turns Hold on and
/// reveals the orange stripe, like the real iPod's switch.
final class HoldSwitchView: UIView {

    /// Called when the user changes the switch.
    var onChange: ((Bool) -> Void)?

    private(set) var isOn: Bool = false

    private let trackLayer = CAGradientLayer()
    private let orangeLayer = CAGradientLayer()
    private let knobLayer = CAGradientLayer()
    private let gripLayer = CAShapeLayer()
    private let label = UILabel()

    private let trackSize = CGSize(width: 34, height: 15)
    private let knobWidth: CGFloat = 19

    private var touchStartX: CGFloat = 0
    private var knobStartX: CGFloat = 0
    private var didDrag = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: trackSize.width + 6 + 34, height: 22)
    }

    private func setup() {
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityLabel = "Hold"
        accessibilityTraits = .button

        // Recessed slot
        trackLayer.colors = [UIColor(white: 0.18, alpha: 1).cgColor, UIColor(white: 0.38, alpha: 1).cgColor]
        trackLayer.cornerRadius = trackSize.height / 2
        trackLayer.masksToBounds = true
        trackLayer.borderWidth = 0.5
        trackLayer.borderColor = UIColor(white: 0.1, alpha: 0.8).cgColor
        layer.addSublayer(trackLayer)

        // Orange stripe, uncovered by the knob when Hold is on
        orangeLayer.colors = [UIColor(red: 0.85, green: 0.38, blue: 0.0, alpha: 1).cgColor,
                              UIColor(red: 1.0, green: 0.6, blue: 0.15, alpha: 1).cgColor]
        orangeLayer.cornerRadius = 2
        trackLayer.addSublayer(orangeLayer)

        // Brushed metal knob
        knobLayer.colors = [UIColor(white: 0.97, alpha: 1).cgColor,
                            UIColor(white: 0.78, alpha: 1).cgColor,
                            UIColor(white: 0.66, alpha: 1).cgColor]
        knobLayer.locations = [0, 0.55, 1]
        knobLayer.cornerRadius = (trackSize.height - 3) / 2
        knobLayer.borderWidth = 0.5
        knobLayer.borderColor = UIColor(white: 0.35, alpha: 1).cgColor
        knobLayer.shadowColor = UIColor.black.cgColor
        knobLayer.shadowOpacity = 0.45
        knobLayer.shadowRadius = 1
        knobLayer.shadowOffset = CGSize(width: 0, height: 0.5)
        trackLayer.addSublayer(knobLayer)

        gripLayer.strokeColor = UIColor(white: 0.5, alpha: 0.8).cgColor
        gripLayer.lineWidth = 0.6
        gripLayer.fillColor = nil
        knobLayer.addSublayer(gripLayer)

        label.text = "HOLD"
        label.font = UIFont(name: "Helvetica-Bold", size: 9)
        label.textColor = UIColor(white: 0.3, alpha: 0.75)
        label.shadowColor = UIColor(white: 1, alpha: 0.5)
        label.shadowOffset = CGSize(width: 0, height: 0.5)
        addSubview(label)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let y = (bounds.height - trackSize.height) / 2
        trackLayer.frame = CGRect(x: 0, y: y, width: trackSize.width, height: trackSize.height)
        orangeLayer.frame = CGRect(x: 4, y: 3.5, width: trackSize.width - knobWidth - 2, height: trackSize.height - 7)
        knobLayer.bounds = CGRect(x: 0, y: 0, width: knobWidth, height: trackSize.height - 3)
        knobLayer.position = CGPoint(x: knobCenterX(on: isOn), y: trackSize.height / 2)
        let path = UIBezierPath()
        for i in -1...1 {
            let x = knobWidth / 2 + CGFloat(i) * 3
            path.move(to: CGPoint(x: x, y: 3))
            path.addLine(to: CGPoint(x: x, y: trackSize.height - 6))
        }
        gripLayer.frame = knobLayer.bounds
        gripLayer.path = path.cgPath
        CATransaction.commit()

        label.sizeToFit()
        label.frame.origin = CGPoint(x: trackSize.width + 6, y: (bounds.height - label.bounds.height) / 2)
    }

    private func knobCenterX(on: Bool) -> CGFloat {
        let minX = 1.5 + knobWidth / 2
        let maxX = trackSize.width - 1.5 - knobWidth / 2
        return on ? maxX : minX
    }

    func setOn(_ on: Bool, animated: Bool) {
        isOn = on
        accessibilityValue = on ? "On" : "Off"
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.15)
        knobLayer.position.x = knobCenterX(on: on)
        CATransaction.commit()
    }

    // Generous hit area; the switch itself is tiny.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return bounds.insetBy(dx: -12, dy: -12).contains(point)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        touchStartX = t.location(in: self).x
        knobStartX = knobLayer.position.x
        didDrag = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let dx = t.location(in: self).x - touchStartX
        if abs(dx) > 3 { didDrag = true }
        guard didDrag else { return }
        let x = min(max(knobStartX + dx, knobCenterX(on: false)), knobCenterX(on: true))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        knobLayer.position.x = x
        CATransaction.commit()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let newValue: Bool
        if didDrag {
            let mid = (knobCenterX(on: false) + knobCenterX(on: true)) / 2
            newValue = knobLayer.position.x >= mid
        } else {
            newValue = !isOn
        }
        commit(newValue)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        setOn(isOn, animated: true)
    }

    override func accessibilityActivate() -> Bool {
        commit(!isOn)
        return true
    }

    private func commit(_ value: Bool) {
        let changed = value != isOn
        setOn(value, animated: true)
        if changed {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            onChange?(value)
        }
    }
}

// MARK: - Padlock graphic

/// A padlock drawn in code, scaling to its bounds (aspect ~ 0.78 : 1).
final class HoldPadlockView: UIView {

    /// Flat glyph for the nav bar, or the glossy metal one for the hold overlay.
    enum Style { case glyph, metal }

    var style: Style = .glyph { didSet { setNeedsDisplay() } }
    var glyphColor: UIColor = UIColor(white: 0.15, alpha: 1) { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        contentMode = .redraw
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        // Fit a 78×100 design box into bounds.
        let scale = min(bounds.width / 78, bounds.height / 100)
        let w = 78 * scale, h = 100 * scale
        let origin = CGPoint(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2)
        func r(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat) -> CGRect {
            CGRect(x: origin.x + x * scale, y: origin.y + y * scale, width: rw * scale, height: rh * scale)
        }

        let bodyRect = r(4, 44, 70, 54)
        let bodyPath = UIBezierPath(roundedRect: bodyRect, cornerRadius: 9 * scale)

        // Shackle: a thick U above the body.
        let shackle = UIBezierPath()
        let sx0 = origin.x + 18 * scale, sx1 = origin.x + 60 * scale
        let sTop = origin.y + 26 * scale
        let sBottom = origin.y + 48 * scale
        let radius = (sx1 - sx0) / 2
        shackle.move(to: CGPoint(x: sx0, y: sBottom))
        shackle.addLine(to: CGPoint(x: sx0, y: sTop))
        shackle.addArc(withCenter: CGPoint(x: sx0 + radius, y: sTop), radius: radius,
                       startAngle: .pi, endAngle: 0, clockwise: true)
        shackle.addLine(to: CGPoint(x: sx1, y: sBottom))
        shackle.lineWidth = 11 * scale
        shackle.lineCapStyle = .butt

        switch style {
        case .glyph:
            glyphColor.setStroke()
            glyphColor.setFill()
            shackle.lineWidth = 12 * scale
            shackle.stroke()
            bodyPath.fill()

        case .metal:
            // Shackle: steel with an outline.
            ctx.saveGState()
            UIColor(white: 0.25, alpha: 1).setStroke()
            let outline = shackle.copy() as! UIBezierPath
            outline.lineWidth = 14 * scale
            outline.stroke()
            ctx.restoreGState()

            ctx.saveGState()
            let shackleOutline = shackle.cgPath.copy(strokingWithWidth: 11 * scale, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
            ctx.addPath(shackleOutline)
            ctx.clip()
            drawGradient(ctx, in: r(0, 0, 78, 50),
                         colors: [UIColor(white: 0.98, alpha: 1), UIColor(white: 0.62, alpha: 1), UIColor(white: 0.85, alpha: 1)],
                         horizontal: true)
            ctx.restoreGState()

            // Body: glossy silver-blue, iPod style.
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 2 * scale), blur: 4 * scale, color: UIColor(white: 0, alpha: 0.4).cgColor)
            UIColor(white: 0.3, alpha: 1).setFill()
            bodyPath.fill()
            ctx.restoreGState()

            ctx.saveGState()
            let inner = UIBezierPath(roundedRect: bodyRect.insetBy(dx: 1.5 * scale, dy: 1.5 * scale), cornerRadius: 8 * scale)
            inner.addClip()
            drawGradient(ctx, in: bodyRect,
                         colors: [UIColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1),
                                  UIColor(red: 0.70, green: 0.74, blue: 0.80, alpha: 1),
                                  UIColor(red: 0.55, green: 0.60, blue: 0.67, alpha: 1)],
                         horizontal: false)
            // Gloss on the upper half
            let gloss = UIBezierPath(rect: CGRect(x: bodyRect.minX, y: bodyRect.minY, width: bodyRect.width, height: bodyRect.height * 0.45))
            UIColor(white: 1, alpha: 0.35).setFill()
            gloss.fill()
            ctx.restoreGState()

            // Keyhole
            let holeCenter = CGPoint(x: bodyRect.midX, y: bodyRect.minY + bodyRect.height * 0.42)
            let hole = UIBezierPath(arcCenter: holeCenter, radius: 6 * scale, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            hole.append(UIBezierPath(roundedRect: CGRect(x: holeCenter.x - 2.5 * scale, y: holeCenter.y,
                                                        width: 5 * scale, height: 15 * scale), cornerRadius: 1.5 * scale))
            UIColor(white: 0.22, alpha: 1).setFill()
            hole.fill()
        }
    }

    private func drawGradient(_ ctx: CGContext, in rect: CGRect, colors: [UIColor], horizontal: Bool) {
        let cgColors = colors.map { $0.cgColor } as CFArray
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil) else { return }
        let start = CGPoint(x: rect.minX, y: rect.minY)
        let end = horizontal ? CGPoint(x: rect.maxX, y: rect.minY) : CGPoint(x: rect.minX, y: rect.maxY)
        ctx.drawLinearGradient(g, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
}

// MARK: - Hold overlay

/// The centred padlock shown on screen when a control is used with Hold on.
final class HoldOverlayView: UIView {

    private let panel = UIView()
    private let padlock = HoldPadlockView()
    private var fadeWork: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        alpha = 0

        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = UIColor(white: 1, alpha: 0.88)
        panel.layer.cornerRadius = 14
        panel.layer.borderWidth = 1
        panel.layer.borderColor = UIColor(white: 0.6, alpha: 1).cgColor
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.35
        panel.layer.shadowRadius = 6
        panel.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(panel)

        padlock.style = .metal
        padlock.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(padlock)

        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: centerYAnchor),
            panel.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.5),
            panel.widthAnchor.constraint(equalTo: panel.heightAnchor),
            padlock.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            padlock.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
            padlock.heightAnchor.constraint(equalTo: panel.heightAnchor, multiplier: 0.7),
            padlock.widthAnchor.constraint(equalTo: padlock.heightAnchor, multiplier: 0.78),
        ])
    }

    /// Shows the padlock, then fades it out ~1.5s after the last call.
    func flash() {
        fadeWork?.cancel()
        if alpha < 1 {
            UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState]) { self.alpha = 1 }
        }
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.4, delay: 0, options: [.beginFromCurrentState]) { self?.alpha = 0 }
        }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func hide() {
        fadeWork?.cancel()
        fadeWork = nil
        layer.removeAllAnimations()
        alpha = 0
    }
}

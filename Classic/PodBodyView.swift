//
//  PodBodyView.swift
//  Classic
//
//  Metal-rendered iPod face (aluminium body + click wheel), drawn by
//  the shader in PodBodyShader.swift. Purely visual: it never takes touches, the existing click
//  wheel views and gesture recognisers sit on top of it unchanged.
//
//  Redraws only when something changes — tilt, a press animation, layout or
//  theme — so it costs nothing while the iPod is idle.
//

import UIKit
import MetalKit
import CoreMotion
import simd

/// Must match PodBodyUniforms in PodBodyShader.swift.
private struct PodBodyUniforms {
    var viewSize: SIMD2<Float>
    var wheelCenter: SIMD2<Float>
    var outerRadius: Float
    var innerRadius: Float
    var scale: Float
    var centerPress: Float
    var bodyColor: SIMD4<Float>
    var wheelColor: SIMD4<Float>
    var centerColor: SIMD4<Float>
    var tilt: SIMD2<Float>
    var pressDir: SIMD2<Float>
    var pressAmount: Float
    var darkness: Float
}

final class PodBodyView: MTKView, MTKViewDelegate {

    enum PressZone { case menu, next, previous, playPause, center }

    /// The click wheel image's frame in this view's coordinates. The ring
    /// geometry is derived from the original artwork's proportions.
    var wheelFrame: CGRect = .zero { didSet { if wheelFrame != oldValue { needsRender = true } } }

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let motion = CMMotionManager()

    private var bodyColor = SIMD4<Float>(0.75, 0.75, 0.75, 1)
    private var wheelColor = SIMD4<Float>(0.75, 0.75, 0.75, 1)
    private var centerColor = SIMD4<Float>(0.83, 0.83, 0.83, 1)
    private var darkness: Float = 0

    private var tilt = SIMD2<Float>(0, 0)
    private var targetTilt = SIMD2<Float>(0, 0)
    private var renderedTilt = SIMD2<Float>(.infinity, .infinity)

    private var pressZone: PressZone?
    private var pressStart: CFTimeInterval = 0
    private let pressDuration: CFTimeInterval = 0.16

    private var needsRender = true

    /// Returns nil when Metal isn't available, so callers can keep the flat artwork.
    static func make() -> PodBodyView? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return PodBodyView(device: device)
    }

    private init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: podBodyShaderSource, options: nil),
              let vertex = library.makeFunction(name: "podBodyVertex"),
              let fragment = library.makeFunction(name: "podBodyFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.commandQueue = queue
        self.pipeline = pipeline
        super.init(frame: .zero, device: device)

        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        isOpaque = true
        isUserInteractionEnabled = false
        preferredFramesPerSecond = 60
        delegate = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        motion.stopDeviceMotionUpdates()
    }

    // MARK: - Public

    func apply(theme: iPodTheme) {
        bodyColor = Self.vector(theme.bodyColor)
        wheelColor = Self.vector(theme.wheelRingColor)
        centerColor = Self.vector(theme.centerButtonColor)
        let luminance = 0.299 * bodyColor.x + 0.587 * bodyColor.y + 0.114 * bodyColor.z
        darkness = max(0, min(1, (0.45 - luminance) / 0.35))
        needsRender = true
    }

    /// Rocks the wheel toward the pressed button (or sinks the centre button).
    func press(_ zone: PressZone) {
        pressZone = zone
        pressStart = CACurrentMediaTime()
        needsRender = true
    }

    // MARK: - Motion

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { startMotion() } else { motion.stopDeviceMotionUpdates() }
        needsRender = true
    }

    private func startMotion() {
        // Tilt-tracked lighting is a nicety; skip it when the user is saving battery.
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive,
              !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let g = data?.gravity else { return }
            // Neutral is the phone held upright and tipped back ~45°.
            let x = Float(max(-1, min(1, g.x * 1.4)))
            let y = Float(max(-1, min(1, (g.z + 0.7) * 1.4)))
            self.targetTilt = SIMD2(x, y)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        needsRender = true
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        needsRender = true
    }

    func draw(in view: MTKView) {
        // Ease the light toward the latest tilt.
        tilt += (targetTilt - tilt) * 0.15
        if simd_length(tilt - renderedTilt) > 0.002 { needsRender = true }

        var pressAmount: Float = 0
        if pressZone != nil {
            let t = (CACurrentMediaTime() - pressStart) / pressDuration
            if t >= 1 {
                pressZone = nil
                needsRender = true
            } else {
                pressAmount = Float(sin(t * .pi))
                needsRender = true
            }
        }

        guard needsRender, bounds.width > 0, wheelFrame.width > 0,
              let drawable = currentDrawable,
              let pass = currentRenderPassDescriptor,
              let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        needsRender = false
        renderedTilt = tilt

        let scale = Float(contentScaleFactor)
        let half = Float(wheelFrame.width) / 2 * scale
        var uniforms = PodBodyUniforms(
            viewSize: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
            wheelCenter: SIMD2(Float(wheelFrame.midX), Float(wheelFrame.midY)) * scale,
            outerRadius: half * 0.968,
            innerRadius: half * 0.348,
            scale: scale,
            centerPress: pressZone == .center ? pressAmount : 0,
            bodyColor: bodyColor,
            wheelColor: wheelColor,
            centerColor: centerColor,
            tilt: tilt,
            pressDir: Self.direction(for: pressZone),
            pressAmount: pressZone == .center ? 0 : pressAmount,
            darkness: darkness
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PodBodyUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    // MARK: - Helpers

    private static func direction(for zone: PressZone?) -> SIMD2<Float> {
        switch zone {
        case .menu: return SIMD2(0, -1)
        case .playPause: return SIMD2(0, 1)
        case .next: return SIMD2(1, 0)
        case .previous: return SIMD2(-1, 0)
        case .center, .none: return SIMD2(0, 0)
        }
    }

    private static func vector(_ color: UIColor) -> SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), 1)
    }
}

//
//  SplitMenuPreview.swift
//  Classic
//
//  iPod classic (6G, 2007) split-screen menus: the list occupies the left half of the
//  screen and the right half previews the highlighted item, crossfading as the wheel moves.
//
//  Adopting it in a menu:
//    1. `private lazy var split = SplitMenuLayout(provider: self)`
//    2. in setupUI: `split.install(tableView: tableView, in: view)` (instead of the 4 edge constraints)
//    3. viewWillAppear: `split.viewWillAppear(selectedRow: counter)`; viewDidDisappear: `split.viewDidDisappear()`
//    4. after every highlight change: `split.selectionDidChange(to: counter)`
//    5. conform to `SplitPreviewProviding`.
//  The layout observes `.splitScreenMenusDidChange` itself, so menus re-layout live.
//

import UIKit
import MediaPlayer
import Photos

// MARK: - Public API

/// What the preview pane shows for a row. Equal kinds share one cached preview view per menu.
enum SplitPreviewKind: Hashable {
    case albumSlideshow                 // Ken-Burns slideshow of library album art
    case albumCollage                   // static grid of album art
    case recentPhotos(albumID: String?) // Ken-Burns of recent photos (nil = whole library)
    case photoGraphic
    case videos
    case extras                         // live clock graphic
    case about                          // "About" info card with gear
    case shuffle
    case nowPlaying
    case clocks, calendars, contacts, alarms, games, notes, screenLock, stopwatch
    case game(String)                   // title card for a game, by menu title
}

protocol SplitPreviewProviding: AnyObject {
    func splitPreviewKind(forRow row: Int) -> SplitPreviewKind?
}

/// Owns the list/preview constraints, the preview pane and the per-row preview cache for one menu.
final class SplitMenuLayout {
    static let listFraction: CGFloat = 0.5

    let pane = SplitPreviewPane()
    private weak var provider: SplitPreviewProviding?
    private weak var container: UIView?
    private var fullWidth: NSLayoutConstraint?
    private var halfWidth: NSLayoutConstraint?
    private var cache: [SplitPreviewKind: UIView] = [:]
    private var row = 0
    private var isVisible = false
    private(set) var isEnabled = false
    private var observer: NSObjectProtocol?

    init(provider: SplitPreviewProviding) {
        self.provider = provider
        observer = NotificationCenter.default.addObserver(forName: .splitScreenMenusDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.applySetting(animated: true)
        }
    }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Adds `tableView` (if needed) and the preview pane to `view` and pins them.
    func install(tableView: UITableView, in view: UIView) {
        guard container == nil else { return }
        container = view
        tableView.translatesAutoresizingMaskIntoConstraints = false
        pane.translatesAutoresizingMaskIntoConstraints = false
        if tableView.superview !== view { view.addSubview(tableView) }
        view.addSubview(pane)

        let full = tableView.rightAnchor.constraint(equalTo: view.rightAnchor)
        let half = tableView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: SplitMenuLayout.listFraction)
        fullWidth = full
        halfWidth = half
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pane.topAnchor.constraint(equalTo: view.topAnchor),
            pane.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pane.leftAnchor.constraint(equalTo: tableView.rightAnchor),
            pane.rightAnchor.constraint(equalTo: view.rightAnchor),
        ])
        isEnabled = SettingsStore.shared.splitScreenMenus
        (isEnabled ? half : full).isActive = true
        pane.isHidden = !isEnabled
    }

    func viewWillAppear(selectedRow: Int) {
        row = selectedRow
        isVisible = true
        applySetting(animated: false)
    }

    /// Stops slideshows/timers. Cached previews are kept for the next appearance.
    func viewDidDisappear() {
        isVisible = false
        pane.setActive(false)
    }

    func selectionDidChange(to newRow: Int) {
        row = newRow
        guard isEnabled, isVisible else { return }
        updatePreview(animated: true)
    }

    /// Drops cached previews (e.g. when the rows' content changed) and rebuilds the current one.
    func reloadPreviews() {
        pane.show(nil, animated: false)
        cache.removeAll()
        if isEnabled && isVisible { updatePreview(animated: false) }
    }

    private func applySetting(animated: Bool) {
        guard let view = container, let full = fullWidth, let half = halfWidth else { return }
        let enabled = SettingsStore.shared.splitScreenMenus
        let changed = enabled != isEnabled
        isEnabled = enabled
        if enabled {
            full.isActive = false
            half.isActive = true
            pane.isHidden = false
            if isVisible { updatePreview(animated: false) }
        } else {
            half.isActive = false
            full.isActive = true
            pane.setActive(false)
        }
        let finish: () -> Void = { [weak self] in
            guard let self = self, !self.isEnabled else { return }
            self.pane.show(nil, animated: false)
            self.pane.isHidden = true
            self.cache.removeAll()
        }
        if animated && changed && view.window != nil {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut], animations: {
                view.layoutIfNeeded()
            }, completion: { _ in finish() })
        } else {
            finish()
        }
    }

    private func updatePreview(animated: Bool) {
        var preview: UIView?
        if let kind = provider?.splitPreviewKind(forRow: row) {
            if let cached = cache[kind] {
                preview = cached
            } else {
                let made = SplitPreviewFactory.make(kind)
                cache[kind] = made
                preview = made
            }
        }
        pane.show(preview, animated: animated && pane.window != nil)
        pane.setActive(isVisible)
    }
}

/// Base class for preview views that animate (slideshows, clocks). The pane activates the visible one.
class SplitPreviewContentView: UIView {
    private(set) var isActive = false

    final func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active { didBecomeActive() } else { didResignActive() }
    }

    func didBecomeActive() {}
    func didResignActive() {}
}

/// The right-hand pane: fills edge to edge, inner shadow at the divider, crossfades between previews.
final class SplitPreviewPane: UIView {
    private let contentHost = UIView()
    private let edgeShadow = CAGradientLayer()
    private let divider = CALayer()
    private(set) var current: UIView?
    private var isActive = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = UIColor(white: 0.86, alpha: 1)
        contentHost.frame = bounds
        contentHost.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentHost.clipsToBounds = true
        addSubview(contentHost)

        edgeShadow.colors = [UIColor(white: 0, alpha: 0.38), UIColor(white: 0, alpha: 0.12), UIColor(white: 0, alpha: 0)].map { $0.cgColor }
        edgeShadow.locations = [0, 0.35, 1]
        edgeShadow.startPoint = CGPoint(x: 0, y: 0.5)
        edgeShadow.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(edgeShadow)
        divider.backgroundColor = UIColor(white: 0.45, alpha: 1).cgColor
        layer.addSublayer(divider)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeShadow.frame = CGRect(x: 0, y: 0, width: 8, height: bounds.height)
        divider.frame = CGRect(x: 0, y: 0, width: 1, height: bounds.height)
        CATransaction.commit()
    }

    func setActive(_ active: Bool) {
        isActive = active
        (current as? SplitPreviewContentView)?.setActive(active)
    }

    func show(_ view: UIView?, animated: Bool) {
        guard view !== current else { return }
        (current as? SplitPreviewContentView)?.setActive(false)
        current = view
        guard let view = view else {
            prune()
            return
        }
        view.layer.removeAllAnimations()
        view.frame = contentHost.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentHost.addSubview(view) // also brings it to the front if it is still fading out
        if isActive { (view as? SplitPreviewContentView)?.setActive(true) }
        if animated {
            view.alpha = 0
            UIView.animate(withDuration: 0.3, delay: 0, options: [.allowUserInteraction, .curveEaseInOut], animations: {
                view.alpha = 1
            }, completion: { [weak self, weak view] finished in
                // An interrupted fade (the view was re-shown) must not pull the views underneath it.
                guard finished, let self = self, let view = view, self.current === view else { return }
                self.prune()
            })
        } else {
            view.alpha = 1
            prune()
        }
    }

    private func prune() {
        for sub in contentHost.subviews where sub !== current {
            sub.removeFromSuperview()
        }
    }
}

// MARK: - Factory

enum SplitPreviewFactory {
    static func make(_ kind: SplitPreviewKind) -> UIView {
        switch kind {
        case .albumSlideshow:
            return SplitKenBurnsView(loader: SplitMediaLoader.albumArtwork,
                                     fallback: SplitPaintView(painter: SplitArt.musicScene))
        case .albumCollage:
            return SplitCollageView(loader: SplitMediaLoader.albumArtwork, overlay: SplitArt.collageVignette,
                                    fallback: SplitArt.musicScene)
        case .recentPhotos(let albumID):
            return SplitKenBurnsView(loader: { SplitMediaLoader.recentPhotos(albumID: albumID, completion: $0) },
                                     fallback: SplitPaintView(painter: SplitArt.photoScene))
        case .photoGraphic:
            return SplitPaintView(painter: SplitArt.photoScene)
        case .videos:
            return SplitPaintView(painter: SplitArt.filmScene)
        case .extras:
            return SplitClockView(style: .plain)
        case .about:
            return SplitAboutView()
        case .shuffle:
            return SplitCollageView(loader: SplitMediaLoader.albumArtwork, overlay: SplitArt.shuffleOverlay,
                                    fallback: SplitArt.shuffleScene)
        case .nowPlaying:
            return SplitNowPlayingView()
        case .clocks:
            return SplitClockView(style: .world)
        case .calendars:
            let v = SplitPaintView(painter: SplitArt.calendarScene)
            v.redrawsOnActivate = true // keep "today" current
            return v
        case .contacts:
            return SplitPaintView(painter: SplitArt.contactsScene)
        case .alarms:
            return SplitPaintView(painter: SplitArt.bellScene)
        case .games:
            return SplitPaintView(painter: SplitArt.gamesMontageScene)
        case .notes:
            return SplitPaintView(painter: SplitArt.notesScene)
        case .screenLock:
            return SplitPaintView(painter: SplitArt.padlockScene)
        case .stopwatch:
            return SplitPaintView(painter: SplitArt.stopwatchScene)
        case .game(let name):
            return SplitPaintView(painter: { ctx, b in SplitArt.gameScene(name, ctx, b) })
        }
    }
}

// MARK: - Media loading (off the main thread, never prompts for access)

enum SplitMediaLoader {
    private static let queue = DispatchQueue(label: "classic.split.preview", qos: .utility)
    static let thumbSize = CGSize(width: 320, height: 320)

    // All of the following statics are only touched on the main thread.
    private static var albumArtCache: [UIImage]?
    private static var albumArtWaiters: [([UIImage]) -> Void] = []
    private static var songCountCache: Int?

    static func albumArtwork(_ completion: @escaping ([UIImage]) -> Void) {
        if let cached = albumArtCache { completion(cached); return }
        guard MPMediaLibrary.authorizationStatus() == .authorized else { completion([]); return }
        albumArtWaiters.append(completion)
        guard albumArtWaiters.count == 1 else { return }
        queue.async {
            let albums = (MPMediaQuery.albums().collections ?? []).shuffled()
            var images: [UIImage] = []
            for album in albums.prefix(60) where images.count < 16 {
                autoreleasepool {
                    if let art = album.representativeItem?.artwork?.image(at: thumbSize) {
                        images.append(art.preparingThumbnail(of: fitted(art.size)) ?? art)
                    }
                }
            }
            DispatchQueue.main.async {
                albumArtCache = images.isEmpty ? nil : images
                let waiters = albumArtWaiters
                albumArtWaiters = []
                waiters.forEach { $0(images) }
            }
        }
    }

    static var cachedSongCount: Int? { songCountCache }

    static func songCount(_ completion: @escaping (Int) -> Void) {
        guard MPMediaLibrary.authorizationStatus() == .authorized else { completion(0); return }
        queue.async {
            let count = MPMediaQuery.songs().items?.count ?? 0
            DispatchQueue.main.async {
                songCountCache = count
                completion(count)
            }
        }
    }

    static var photosAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    static func recentPhotos(albumID: String?, completion: @escaping ([UIImage]) -> Void) {
        guard photosAuthorized else { completion([]); return }
        queue.async {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = 8
            let assets: PHFetchResult<PHAsset>
            if let id = albumID,
               let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject {
                options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
                assets = PHAsset.fetchAssets(in: collection, options: options)
            } else {
                assets = PHAsset.fetchAssets(with: .image, options: options)
            }
            let request = PHImageRequestOptions()
            request.isSynchronous = true
            request.deliveryMode = .highQualityFormat
            request.resizeMode = .fast
            request.isNetworkAccessAllowed = false
            var images: [UIImage] = []
            assets.enumerateObjects { asset, _, _ in
                autoreleasepool {
                    PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 400, height: 400),
                                                          contentMode: .aspectFill, options: request) { image, _ in
                        if let image = image { images.append(image) }
                    }
                }
            }
            DispatchQueue.main.async { completion(images) }
        }
    }

    static func artwork(_ artwork: MPMediaItemArtwork, completion: @escaping (UIImage?) -> Void) {
        queue.async {
            let image = artwork.image(at: CGSize(width: 400, height: 400))
            let small = image.flatMap { $0.preparingThumbnail(of: fitted($0.size, max: 400)) ?? $0 }
            DispatchQueue.main.async { completion(small) }
        }
    }

    private static func fitted(_ size: CGSize, max side: CGFloat = 320) -> CGSize {
        guard size.width > 0, size.height > 0 else { return thumbSize }
        let scale = min(1, side / Swift.max(size.width, size.height))
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    static let capacityString: String = {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let total = attrs[.systemSize] as? Int64 {
            let gb = Double(total) / 1_000_000_000
            // Round to the marketed size, like the iPod's own About screen.
            let marketed = [16.0, 32, 64, 128, 256, 512, 1024, 2048].first { $0 >= gb * 0.9 } ?? gb.rounded()
            return marketed >= 1024 ? String(format: "%.0fTB", marketed / 1024) : String(format: "%.0fGB", marketed)
        }
        return "160GB"
    }()
}

// MARK: - Preview views

/// A preview drawn entirely in Core Graphics (background included).
final class SplitPaintView: SplitPreviewContentView {
    typealias Painter = (CGContext, CGRect) -> Void
    private let painter: Painter
    var redrawsOnActivate = false

    init(painter: @escaping Painter) {
        self.painter = painter
        super.init(frame: .zero)
        contentMode = .redraw
        isOpaque = true
        backgroundColor = .white
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), bounds.width > 0, bounds.height > 0 else { return }
        painter(ctx, bounds)
    }

    override func didBecomeActive() {
        if redrawsOnActivate { setNeedsDisplay() }
    }
}

/// Slow pan/zoom slideshow, crossfading to the next image every few seconds.
final class SplitKenBurnsView: SplitPreviewContentView {
    typealias Loader = (@escaping ([UIImage]) -> Void) -> Void
    static let interval: TimeInterval = 4

    private let loader: Loader
    private let fallback: UIView
    private let imageViews = [UIImageView(), UIImageView()]
    private var images: [UIImage] = []
    private var index = 0
    private var front = 0
    private var timer: Timer?
    private var isLoading = false

    init(loader: @escaping Loader, fallback: UIView) {
        self.loader = loader
        self.fallback = fallback
        super.init(frame: .zero)
        clipsToBounds = true
        backgroundColor = .black
        isUserInteractionEnabled = false
        fallback.frame = bounds
        fallback.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(fallback)
        for iv in imageViews {
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            iv.alpha = 0
            addSubview(iv)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Image views carry transforms, so size them via bounds/center rather than frame.
        for iv in imageViews {
            iv.bounds = CGRect(origin: .zero, size: bounds.size)
            iv.center = CGPoint(x: bounds.midX, y: bounds.midY)
        }
    }

    override func didBecomeActive() {
        if images.isEmpty {
            load()
        } else {
            advance(animated: true)
            startTimer()
        }
    }

    override func didResignActive() {
        // Keep the current pan running so the crossfade out of this preview doesn't jump;
        // nothing new is scheduled once the timer is gone.
        timer?.invalidate()
        timer = nil
    }

    private func load() {
        guard !isLoading else { return }
        isLoading = true
        loader { [weak self] loaded in
            guard let self = self else { return }
            self.isLoading = false
            self.images = loaded
            self.fallback.isHidden = !loaded.isEmpty
            guard !loaded.isEmpty, self.isActive else { return }
            self.index = 0
            self.advance(animated: true)
            self.startTimer()
        }
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: SplitKenBurnsView.interval, repeats: true) { [weak self] _ in
            self?.advance(animated: true)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func advance(animated: Bool) {
        guard !images.isEmpty else { return }
        let outgoing = imageViews[front]
        let incoming = imageViews[1 - front]
        front = 1 - front
        incoming.layer.removeAllAnimations()
        incoming.image = images[index % images.count]
        index += 1
        let (start, end) = randomPan()
        incoming.transform = start
        bringSubviewToFront(incoming)
        incoming.alpha = animated ? 0 : 1
        UIView.animate(withDuration: animated ? 0.9 : 0, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: {
            incoming.alpha = 1
        }, completion: { [weak self] _ in
            guard let self = self, self.imageViews[self.front] !== outgoing else { return }
            outgoing.alpha = 0
        })
        UIView.animate(withDuration: SplitKenBurnsView.interval + 1.5, delay: 0, options: [.curveLinear, .allowUserInteraction], animations: {
            incoming.transform = end
        })
    }

    private func randomPan() -> (CGAffineTransform, CGAffineTransform) {
        func make(_ scale: CGFloat) -> CGAffineTransform {
            // Keep the image covering the pane: translation never exceeds the scaled overhang.
            let maxX = (scale - 1) * bounds.width / 2 * 0.9
            let maxY = (scale - 1) * bounds.height / 2 * 0.9
            let tx = CGFloat.random(in: -1...1) * maxX
            let ty = CGFloat.random(in: -1...1) * maxY
            return CGAffineTransform(translationX: tx, y: ty).scaledBy(x: scale, y: scale)
        }
        let zoomIn = Bool.random()
        let a = make(CGFloat.random(in: 1.04...1.08))
        let b = make(CGFloat.random(in: 1.18...1.25))
        return zoomIn ? (a, b) : (b, a)
    }
}

/// Grid of images (album art) with an optional overlay painter.
final class SplitCollageView: SplitPreviewContentView {
    private let loader: SplitKenBurnsView.Loader
    private let overlay: SplitPaintView.Painter?
    private let fallback: SplitPaintView.Painter
    private var images: [UIImage] = []
    private var isLoading = false

    init(loader: @escaping SplitKenBurnsView.Loader, overlay: SplitPaintView.Painter?, fallback: @escaping SplitPaintView.Painter) {
        self.loader = loader
        self.overlay = overlay
        self.fallback = fallback
        super.init(frame: .zero)
        contentMode = .redraw
        isOpaque = true
        backgroundColor = .black
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didBecomeActive() {
        guard images.isEmpty, !isLoading else { return }
        isLoading = true
        loader { [weak self] loaded in
            guard let self = self else { return }
            self.isLoading = false
            self.images = loaded
            if !loaded.isEmpty { self.setNeedsDisplay() }
        }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), bounds.width > 0 else { return }
        guard !images.isEmpty else { fallback(ctx, bounds); return }
        UIColor.black.setFill()
        ctx.fill(bounds)
        let cols: CGFloat = 2
        let tile = ceil(bounds.width / cols)
        let rows = Int(ceil(bounds.height / tile))
        // Offset rows so the collage looks staggered rather than a plain repeat.
        for r in 0..<rows {
            for c in 0..<Int(cols) {
                let i = (r * Int(cols) + c + r) % images.count
                let cell = CGRect(x: CGFloat(c) * tile, y: CGFloat(r) * tile, width: tile, height: tile).insetBy(dx: 0.5, dy: 0.5)
                SplitArt.drawAspectFill(images[i], in: cell, ctx)
            }
        }
        overlay?(ctx, bounds)
    }
}

/// Live analog clock: `.plain` on the soft gradient (Home › Extras), `.world` over a blue world grid (Extras › Clocks).
final class SplitClockView: SplitPreviewContentView {
    enum Style { case plain, world }

    private let style: Style
    private let backdrop: SplitPaintView
    private let clock = AnalogClockView()
    private let dateLabel = UILabel()
    private let cityLabel = UILabel()
    private var timer: Timer?
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f
    }()

    init(style: Style) {
        self.style = style
        backdrop = SplitPaintView(painter: style == .world ? SplitArt.worldGrid : SplitArt.softBackground)
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backdrop.frame = bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(backdrop)
        clock.faceStyle = style == .world ? .automatic : .day
        clock.showsSecondHand = true
        addSubview(clock)
        if style == .world {
            for label in [dateLabel, cityLabel] {
                label.textAlignment = .center
                label.textColor = .white
                label.adjustsFontSizeToFitWidth = true
                label.minimumScaleFactor = 0.7
                label.layer.shadowColor = UIColor.black.cgColor
                label.layer.shadowOpacity = 0.5
                label.layer.shadowRadius = 1
                label.layer.shadowOffset = CGSize(width: 0, height: 1)
                addSubview(label)
            }
            dateLabel.font = SplitArt.font(14)
            cityLabel.font = UIFont(name: "Helvetica", size: 11)
            cityLabel.alpha = 0.85
            let id = TimeZone.current.identifier
            cityLabel.text = (id.split(separator: "/").last.map(String.init) ?? id).replacingOccurrences(of: "_", with: " ")
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        if style == .world {
            let side = min(b.width * 0.66, b.height * 0.55)
            clock.frame = CGRect(x: b.midX - side / 2, y: b.height * 0.42 - side / 2, width: side, height: side)
            dateLabel.frame = CGRect(x: 8, y: clock.frame.maxY + 6, width: b.width - 16, height: 18)
            cityLabel.frame = CGRect(x: 8, y: dateLabel.frame.maxY + 1, width: b.width - 16, height: 15)
        } else {
            let side = min(b.width, b.height) * 0.66
            clock.frame = CGRect(x: b.midX - side / 2, y: b.midY - side / 2, width: side, height: side)
        }
    }

    override func didBecomeActive() {
        tick()
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    override func didResignActive() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = Date()
        clock.update(to: now)
        if style == .world { dateLabel.text = SplitClockView.dateFormatter.string(from: now) }
    }
}

/// Current track's artwork full-bleed with title/artist on a dark band.
final class SplitNowPlayingView: SplitPreviewContentView {
    private let fallback = SplitPaintView(painter: SplitArt.musicScene)
    private let artView = UIImageView()
    private let band = UIView()
    private let bandGradient = CAGradientLayer()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private var observer: NSObjectProtocol?
    private var shownID: MPMediaEntityPersistentID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
        for v in [fallback, artView] as [UIView] {
            v.frame = bounds
            v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(v)
        }
        artView.contentMode = .scaleAspectFill
        artView.clipsToBounds = true
        bandGradient.colors = [UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0.78)].map { $0.cgColor }
        band.layer.addSublayer(bandGradient)
        addSubview(band)
        titleLabel.font = SplitArt.font(13)
        artistLabel.font = UIFont(name: "Helvetica", size: 11)
        for label in [titleLabel, artistLabel] {
            label.textColor = .white
            label.lineBreakMode = .byTruncatingTail
            band.addSubview(label)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = max(48, bounds.height * 0.3)
        band.frame = CGRect(x: 0, y: bounds.height - h, width: bounds.width, height: h)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bandGradient.frame = band.bounds
        CATransaction.commit()
        artistLabel.frame = CGRect(x: 12, y: h - 22, width: bounds.width - 20, height: 15)
        titleLabel.frame = CGRect(x: 12, y: h - 39, width: bounds.width - 20, height: 17)
    }

    override func didBecomeActive() {
        refresh()
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
                                                              object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        }
    }

    override func didResignActive() {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func refresh() {
        let item = AppDelegate.music.musicPlayer.nowPlayingItem
        titleLabel.text = item?.title ?? "Not Playing"
        artistLabel.text = item?.artist ?? item?.albumTitle ?? ""
        let id = item?.persistentID
        guard id != shownID || artView.image == nil else { return }
        shownID = id
        artView.image = nil
        guard let artwork = item?.artwork else { return }
        SplitMediaLoader.artwork(artwork) { [weak self] image in
            guard let self = self, self.shownID == id else { return }
            self.artView.image = image
        }
    }
}

/// "About"-style card: gear, model text, song count and capacity.
final class SplitAboutView: SplitPreviewContentView {
    private var songCount: Int? = SplitMediaLoader.cachedSongCount

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .redraw
        isOpaque = true
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didBecomeActive() {
        setNeedsDisplay() // pick up colour changes
        SplitMediaLoader.songCount { [weak self] count in
            guard let self = self, count != self.songCount else { return }
            self.songCount = count
            self.setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), bounds.width > 0 else { return }
        let b = bounds
        SplitArt.softBackground(ctx, b)
        let gearR = min(b.width * 0.22, b.height * 0.17)
        let gearC = CGPoint(x: b.midX, y: b.minY + b.height * 0.07 + gearR)
        SplitArt.gear(ctx, center: gearC, radius: gearR)

        var y = gearC.y + gearR + 8
        SplitArt.text("Classic", CGRect(x: 8, y: y, width: b.width - 16, height: 20), size: 16, color: UIColor(white: 0.1, alpha: 1))
        y += 19
        let model = "iPod classic · \(ThemeManager.shared.currentTheme.name)"
        SplitArt.text(model, CGRect(x: 8, y: y, width: b.width - 16, height: 16), size: 11, color: UIColor(white: 0.4, alpha: 1), bold: false)
        y += 22

        let songs = songCount.map { NumberFormatter.localizedString(from: NSNumber(value: $0), number: .decimal) } ?? "–"
        let rows = [("Songs", songs), ("Capacity", SplitMediaLoader.capacityString),
                    ("Version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")]
        let inset: CGFloat = 14
        for (label, value) in rows {
            guard y + 18 <= b.maxY - 4 else { break }
            UIColor(white: 0.62, alpha: 1).setFill()
            ctx.fill(CGRect(x: inset, y: y, width: b.width - inset * 2, height: 0.5))
            let row = CGRect(x: inset, y: y + 1, width: b.width - inset * 2, height: 18)
            SplitArt.text(label, row, size: 12, color: UIColor(white: 0.15, alpha: 1), align: .left)
            SplitArt.text(value, row, size: 12, color: UIColor(white: 0.35, alpha: 1), bold: false, align: .right)
            y += 19
        }
    }
}

// MARK: - Drawing

/// Code-drawn preview artwork in the 2007 iPod style: glossy gradients, soft shadows, Helvetica Bold.
enum SplitArt {
    static func font(_ size: CGFloat, bold: Bool = true) -> UIFont {
        UIFont(name: bold ? "Helvetica-Bold" : "Helvetica", size: size) ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    // MARK: Primitives

    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: a)
    }

    static func gradient(_ ctx: CGContext, _ colors: [UIColor], from p0: CGPoint, to p1: CGPoint, locations: [CGFloat]? = nil) {
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map { $0.cgColor } as CFArray,
                                 locations: locations) else { return }
        ctx.drawLinearGradient(g, start: p0, end: p1, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    static func fill(_ ctx: CGContext, _ path: UIBezierPath, _ colors: [UIColor], vertical: Bool = true, locations: [CGFloat]? = nil) {
        let r = path.bounds
        ctx.saveGState()
        ctx.addPath(path.cgPath)
        ctx.clip()
        gradient(ctx, colors, from: CGPoint(x: r.minX, y: r.minY),
                 to: vertical ? CGPoint(x: r.minX, y: r.maxY) : CGPoint(x: r.maxX, y: r.minY), locations: locations)
        ctx.restoreGState()
    }

    static func withShadow(_ ctx: CGContext, blur: CGFloat = 5, offset: CGSize = CGSize(width: 0, height: 2),
                           alpha: CGFloat = 0.35, _ body: () -> Void) {
        ctx.saveGState()
        ctx.setShadow(offset: offset, blur: blur, color: UIColor(white: 0, alpha: alpha).cgColor)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// Classic top-half gloss highlight clipped to `path`.
    static func gloss(_ ctx: CGContext, _ path: UIBezierPath, strength: CGFloat = 0.5) {
        let r = path.bounds
        ctx.saveGState()
        ctx.addPath(path.cgPath)
        ctx.clip()
        let glossRect = CGRect(x: r.minX - r.width * 0.25, y: r.minY - r.height * 0.6, width: r.width * 1.5, height: r.height * 1.1)
        ctx.addEllipse(in: glossRect)
        ctx.clip()
        gradient(ctx, [UIColor(white: 1, alpha: strength), UIColor(white: 1, alpha: strength * 0.15)],
                 from: CGPoint(x: r.midX, y: r.minY), to: CGPoint(x: r.midX, y: glossRect.maxY))
        ctx.restoreGState()
    }

    static func text(_ string: String, _ rect: CGRect, size: CGFloat, color: UIColor, bold: Bool = true,
                     align: NSTextAlignment = .center) {
        let para = NSMutableParagraphStyle()
        para.alignment = align
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: font(size, bold: bold), .foregroundColor: color, .paragraphStyle: para]
        let h = (string as NSString).size(withAttributes: attrs).height
        (string as NSString).draw(in: CGRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h), withAttributes: attrs)
    }

    /// Centred box of the given aspect (w/h) taking `fraction` of the limiting dimension.
    static func box(_ b: CGRect, _ fraction: CGFloat, aspect: CGFloat = 1) -> CGRect {
        let h = min(b.height * fraction, b.width * fraction / aspect)
        let w = h * aspect
        return CGRect(x: b.midX - w / 2, y: b.midY - h / 2, width: w, height: h).integral
    }

    static func drawAspectFill(_ image: UIImage, in r: CGRect, _ ctx: CGContext) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(r.width / image.size.width, r.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        ctx.saveGState()
        ctx.clip(to: r)
        image.draw(in: CGRect(x: r.midX - size.width / 2, y: r.midY - size.height / 2, width: size.width, height: size.height))
        ctx.restoreGState()
    }

    static func softBackground(_ ctx: CGContext, _ b: CGRect) {
        gradient(ctx, [UIColor(white: 0.99, alpha: 1), UIColor(white: 0.90, alpha: 1), UIColor(white: 0.78, alpha: 1)],
                 from: CGPoint(x: b.midX, y: b.minY), to: CGPoint(x: b.midX, y: b.maxY), locations: [0, 0.55, 1])
    }

    /// Soft background with a reflection-like floor shadow under the icon.
    static func scene(_ ctx: CGContext, _ b: CGRect, icon: CGRect) {
        softBackground(ctx, b)
        ctx.saveGState()
        let floor = CGRect(x: icon.minX + icon.width * 0.1, y: icon.maxY - icon.height * 0.02, width: icon.width * 0.8, height: icon.height * 0.12)
        ctx.addEllipse(in: floor)
        ctx.clip()
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [UIColor(white: 0, alpha: 0.18).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray, locations: nil) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: floor.midX, y: floor.midY), startRadius: 0,
                                   endCenter: CGPoint(x: floor.midX, y: floor.midY), endRadius: floor.width / 2, options: [])
        }
        ctx.restoreGState()
    }

    // MARK: Music

    static func musicNote(_ ctx: CGContext, _ r: CGRect, color: UIColor) {
        let u = r.width
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * u, y: r.minY + y * u) }
        color.setFill()
        for (cx, cy) in [(0.30, 0.76), (0.72, 0.68)] as [(CGFloat, CGFloat)] {
            ctx.saveGState()
            ctx.translateBy(x: r.minX + cx * u, y: r.minY + cy * u)
            ctx.rotate(by: -0.4)
            UIBezierPath(ovalIn: CGRect(x: -0.13 * u, y: -0.09 * u, width: 0.26 * u, height: 0.18 * u)).fill()
            ctx.restoreGState()
        }
        UIBezierPath(rect: CGRect(x: r.minX + 0.37 * u, y: r.minY + 0.24 * u, width: 0.055 * u, height: 0.49 * u)).fill()
        UIBezierPath(rect: CGRect(x: r.minX + 0.79 * u, y: r.minY + 0.15 * u, width: 0.055 * u, height: 0.50 * u)).fill()
        let beam = UIBezierPath()
        beam.move(to: p(0.37, 0.22))
        beam.addLine(to: p(0.845, 0.12))
        beam.addLine(to: p(0.845, 0.24))
        beam.addLine(to: p(0.37, 0.34))
        beam.close()
        beam.fill()
    }

    static func glossyBadge(_ ctx: CGContext, _ r: CGRect, colors: [UIColor]) -> UIBezierPath {
        let path = UIBezierPath(roundedRect: r, cornerRadius: r.width * 0.22)
        withShadow(ctx, blur: 6, offset: CGSize(width: 0, height: 3), alpha: 0.4) {
            fill(ctx, path, colors)
        }
        return path
    }

    static func musicScene(_ ctx: CGContext, _ b: CGRect) {
        let r = box(b, 0.55)
        scene(ctx, b, icon: r)
        let path = glossyBadge(ctx, r, colors: [UIColor.gradientLightBlue, UIColor.gradientDarkBlue])
        withShadow(ctx, blur: 2, offset: CGSize(width: 0, height: 1), alpha: 0.35) {
            musicNote(ctx, r.insetBy(dx: r.width * 0.18, dy: r.width * 0.18), color: .white)
        }
        gloss(ctx, path, strength: 0.55)
        UIColor(white: 0, alpha: 0.25).setStroke()
        path.lineWidth = 0.75
        path.stroke()
    }

    static func shuffleArrows(_ ctx: CGContext, _ r: CGRect, color: UIColor) {
        let u = r.width
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * u, y: r.minY + y * u) }
        color.setStroke()
        color.setFill()
        for (a, b) in [(0.70, 0.30), (0.30, 0.70)] as [(CGFloat, CGFloat)] {
            let path = UIBezierPath()
            path.move(to: p(0.06, a))
            path.addLine(to: p(0.26, a))
            path.addCurve(to: p(0.64, b), controlPoint1: p(0.48, a), controlPoint2: p(0.44, b))
            path.addLine(to: p(0.76, b))
            path.lineWidth = u * 0.085
            path.stroke()
            let head = UIBezierPath()
            head.move(to: p(0.75, b - 0.12))
            head.addLine(to: p(0.95, b))
            head.addLine(to: p(0.75, b + 0.12))
            head.close()
            head.fill()
        }
    }

    static func shuffleScene(_ ctx: CGContext, _ b: CGRect) {
        let r = box(b, 0.55)
        scene(ctx, b, icon: r)
        let path = glossyBadge(ctx, r, colors: [rgb(0.55, 0.85, 0.35), rgb(0.20, 0.58, 0.12)])
        withShadow(ctx, blur: 2, offset: CGSize(width: 0, height: 1), alpha: 0.35) {
            shuffleArrows(ctx, r.insetBy(dx: r.width * 0.16, dy: r.width * 0.16), color: .white)
        }
        gloss(ctx, path)
    }

    static func shuffleOverlay(_ ctx: CGContext, _ b: CGRect) {
        UIColor(white: 0, alpha: 0.45).setFill()
        ctx.fill(b)
        let r = box(b, 0.5)
        withShadow(ctx, blur: 6, offset: CGSize(width: 0, height: 2), alpha: 0.7) {
            shuffleArrows(ctx, r, color: .white)
        }
    }

    static func collageVignette(_ ctx: CGContext, _ b: CGRect) {
        gradient(ctx, [UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0.35)],
                 from: CGPoint(x: b.midX, y: b.midY), to: CGPoint(x: b.midX, y: b.maxY))
    }

    // MARK: Photos & video

    static func landscape(_ ctx: CGContext, _ r: CGRect, warm: Bool) {
        ctx.saveGState()
        ctx.clip(to: r)
        gradient(ctx, warm ? [rgb(0.98, 0.62, 0.30), rgb(1, 0.88, 0.62)] : [rgb(0.25, 0.55, 0.92), rgb(0.70, 0.86, 1)],
                 from: CGPoint(x: r.midX, y: r.minY), to: CGPoint(x: r.midX, y: r.maxY))
        (warm ? rgb(1, 0.95, 0.75) : rgb(1, 0.93, 0.45)).setFill()
        ctx.fillEllipse(in: CGRect(x: r.minX + r.width * 0.64, y: r.minY + r.height * 0.16, width: r.width * 0.18, height: r.width * 0.18))
        let far = UIBezierPath()
        far.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.66))
        far.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.6), controlPoint: CGPoint(x: r.midX, y: r.minY + r.height * 0.38))
        far.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        far.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        far.close()
        fill(ctx, far, warm ? [rgb(0.55, 0.42, 0.30), rgb(0.35, 0.25, 0.18)] : [rgb(0.45, 0.70, 0.35), rgb(0.25, 0.48, 0.20)])
        let near = UIBezierPath()
        near.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.82))
        near.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.78), controlPoint: CGPoint(x: r.minX + r.width * 0.3, y: r.minY + r.height * 0.6))
        near.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        near.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        near.close()
        fill(ctx, near, warm ? [rgb(0.45, 0.30, 0.20), rgb(0.28, 0.18, 0.10)] : [rgb(0.35, 0.60, 0.25), rgb(0.18, 0.38, 0.12)])
        ctx.restoreGState()
    }

    static func photoPrint(_ ctx: CGContext, center: CGPoint, size: CGSize, angle: CGFloat, warm: Bool) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: angle)
        let frame = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        withShadow(ctx, blur: 5, offset: CGSize(width: 0, height: 2), alpha: 0.4) {
            UIColor.white.setFill()
            ctx.fill(frame)
        }
        let border = size.width * 0.06
        landscape(ctx, CGRect(x: frame.minX + border, y: frame.minY + border, width: frame.width - border * 2, height: frame.height - border * 2), warm: warm)
        UIColor(white: 0.75, alpha: 1).setStroke()
        ctx.setLineWidth(0.5)
        ctx.stroke(frame)
        ctx.restoreGState()
    }

    static func photoScene(_ ctx: CGContext, _ b: CGRect) {
        let r = box(b, 0.62, aspect: 1.2)
        scene(ctx, b, icon: r)
        let size = CGSize(width: r.width * 0.8, height: r.height * 0.78)
        photoPrint(ctx, center: CGPoint(x: r.midX - r.width * 0.07, y: r.midY - r.height * 0.06), size: size, angle: -0.17, warm: true)
        photoPrint(ctx, center: CGPoint(x: r.midX + r.width * 0.06, y: r.midY + r.height * 0.06), size: size, angle: 0.08, warm: false)
    }

    static func filmScene(_ ctx: CGContext, _ b: CGRect) {
        softBackground(ctx, b)
        let stripH = min(b.height * 0.42, b.width * 0.55)
        ctx.saveGState()
        ctx.translateBy(x: b.midX, y: b.midY)
        ctx.rotate(by: -0.22)
        let strip = CGRect(x: -b.width * 0.75, y: -stripH / 2, width: b.width * 1.5, height: stripH)
        withShadow(ctx, blur: 6, offset: CGSize(width: 0, height: 3), alpha: 0.45) {
            fill(ctx, UIBezierPath(rect: strip), [UIColor(white: 0.22, alpha: 1), UIColor(white: 0.05, alpha: 1)])
        }
        let hole = CGSize(width: stripH * 0.085, height: stripH * 0.07)
        var x = strip.minX + hole.width * 0.5
        UIColor(white: 0.93, alpha: 1).setFill()
        while x < strip.maxX {
            for y in [strip.minY + stripH * 0.05, strip.maxY - stripH * 0.05 - hole.height] {
                UIBezierPath(roundedRect: CGRect(x: x, y: y, width: hole.width, height: hole.height), cornerRadius: hole.height * 0.25).fill()
            }
            x += hole.width * 2
        }
        let frameH = stripH * 0.66
        let frameW = frameH * 1.3
        let gap = stripH * 0.08
        var fx = -frameW * 1.5 - gap
        var warm = false
        while fx < strip.maxX {
            if fx + frameW > strip.minX {
                landscape(ctx, CGRect(x: fx, y: -frameH / 2, width: frameW, height: frameH), warm: warm)
            }
            warm.toggle()
            fx += frameW + gap
        }
        ctx.restoreGState()
        // Glossy play button
        let d = min(b.width, b.height) * 0.26
        let circle = UIBezierPath(ovalIn: CGRect(x: b.midX - d / 2, y: b.midY - d / 2, width: d, height: d))
        withShadow(ctx, blur: 5, offset: CGSize(width: 0, height: 2), alpha: 0.5) {
            fill(ctx, circle, [UIColor.gradientLightBlue, UIColor.gradientDarkBlue])
        }
        let tri = UIBezierPath()
        tri.move(to: CGPoint(x: b.midX - d * 0.14, y: b.midY - d * 0.22))
        tri.addLine(to: CGPoint(x: b.midX + d * 0.24, y: b.midY))
        tri.addLine(to: CGPoint(x: b.midX - d * 0.14, y: b.midY + d * 0.22))
        tri.close()
        UIColor.white.setFill()
        tri.fill()
        gloss(ctx, circle, strength: 0.6)
        UIColor(white: 1, alpha: 0.8).setStroke()
        circle.lineWidth = 1.5
        circle.stroke()
    }

    // MARK: Settings

    static func gear(_ ctx: CGContext, center c: CGPoint, radius R: CGFloat, teeth n: Int = 12) {
        let path = UIBezierPath()
        let inner = R * 0.8
        let step = 2 * CGFloat.pi / CGFloat(n)
        func pt(_ r: CGFloat, _ a: CGFloat) -> CGPoint { CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)) }
        for i in 0..<n {
            let a = CGFloat(i) * step
            if i == 0 { path.move(to: pt(inner, a)) } else { path.addLine(to: pt(inner, a)) }
            path.addLine(to: pt(R, a + step * 0.14))
            path.addLine(to: pt(R, a + step * 0.40))
            path.addLine(to: pt(inner, a + step * 0.54))
        }
        path.close()
        let hole = UIBezierPath(ovalIn: CGRect(x: c.x - R * 0.28, y: c.y - R * 0.28, width: R * 0.56, height: R * 0.56))
        path.append(hole)
        path.usesEvenOddFillRule = true
        withShadow(ctx, blur: 5, offset: CGSize(width: 0, height: 2), alpha: 0.4) {
            ctx.saveGState()
            ctx.addPath(path.cgPath)
            ctx.clip(using: .evenOdd)
            gradient(ctx, [UIColor(white: 0.96, alpha: 1), UIColor(white: 0.72, alpha: 1), UIColor(white: 0.5, alpha: 1)],
                     from: CGPoint(x: c.x, y: c.y - R), to: CGPoint(x: c.x, y: c.y + R))
            ctx.restoreGState()
        }
        let ring = UIBezierPath(ovalIn: CGRect(x: c.x - R * 0.58, y: c.y - R * 0.58, width: R * 1.16, height: R * 1.16))
        ring.lineWidth = max(1, R * 0.05)
        UIColor(white: 0.55, alpha: 0.6).setStroke()
        ring.stroke()
        UIColor(white: 0.35, alpha: 0.7).setStroke()
        path.lineWidth = 0.75
        path.stroke()
    }

    // MARK: Extras

    static func worldGrid(_ ctx: CGContext, _ b: CGRect) {
        gradient(ctx, [rgb(0.30, 0.58, 0.92), rgb(0.08, 0.28, 0.65), rgb(0.03, 0.12, 0.35)],
                 from: CGPoint(x: b.midX, y: b.minY), to: CGPoint(x: b.midX, y: b.maxY), locations: [0, 0.55, 1])
        let c = CGPoint(x: b.midX, y: b.height * 0.42)
        let R = max(b.width, b.height) * 0.62
        ctx.saveGState()
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.16).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2))
        for k in [0.2, 0.45, 0.7, 0.9] as [CGFloat] {
            ctx.strokeEllipse(in: CGRect(x: c.x - R * k, y: c.y - R, width: R * k * 2, height: R * 2))
        }
        ctx.move(to: CGPoint(x: c.x, y: c.y - R)); ctx.addLine(to: CGPoint(x: c.x, y: c.y + R))
        for k in [-0.75, -0.5, -0.25, 0, 0.25, 0.5, 0.75] as [CGFloat] {
            let y = c.y + R * k
            let half = R * sqrt(1 - k * k)
            ctx.move(to: CGPoint(x: c.x - half, y: y)); ctx.addLine(to: CGPoint(x: c.x + half, y: y))
        }
        ctx.strokePath()
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [UIColor(white: 1, alpha: 0.22).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray, locations: nil) {
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: min(b.width, b.height) * 0.6, options: [])
        }
        ctx.restoreGState()
    }

    private static let monthFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMMM"; return f }()
    private static let weekdayFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE"; return f }()

    static func calendarScene(_ ctx: CGContext, _ b: CGRect) {
        let r = box(b, 0.68, aspect: 0.88)
        scene(ctx, b, icon: r)
        let now = Date()
        // Pages underneath, for the tear-off pad look.
        for (i, shade) in [(2, 0.80), (1, 0.88)] as [(CGFloat, CGFloat)] {
            let under = UIBezierPath(roundedRect: r.offsetBy(dx: 0, dy: i * 3), cornerRadius: r.width * 0.05)
            withShadow(ctx, blur: 2, offset: CGSize(width: 0, height: 1), alpha: 0.25) {
                UIColor(white: shade, alpha: 1).setFill()
                under.fill()
            }
        }
        let page = UIBezierPath(roundedRect: r, cornerRadius: r.width * 0.05)
        withShadow(ctx, blur: 4, offset: CGSize(width: 0, height: 2), alpha: 0.3) {
            fill(ctx, page, [UIColor.white, UIColor(white: 0.93, alpha: 1)])
        }
        let headerH = r.height * 0.26
        ctx.saveGState()
        ctx.addPath(page.cgPath)
        ctx.clip()
        let header = CGRect(x: r.minX, y: r.minY, width: r.width, height: headerH)
        fill(ctx, UIBezierPath(rect: header), [rgb(0.92, 0.28, 0.24), rgb(0.66, 0.06, 0.06)])
        gloss(ctx, UIBezierPath(rect: header), strength: 0.35)
        ctx.restoreGState()
        text(monthFormatter.string(from: now).uppercased(), header.offsetBy(dx: 0, dy: headerH * 0.08),
             size: headerH * 0.42, color: .white)
        let day = Calendar.current.component(.day, from: now)
        text("\(day)", CGRect(x: r.minX, y: r.minY + headerH, width: r.width, height: r.height * 0.52),
             size: r.height * 0.42, color: UIColor(white: 0.12, alpha: 1))
        text(weekdayFormatter.string(from: now), CGRect(x: r.minX + 4, y: r.maxY - r.height * 0.22, width: r.width - 8, height: r.height * 0.18),
             size: r.height * 0.09, color: UIColor(white: 0.45, alpha: 1))
        // Binding rings
        for fx in [0.28, 0.72] as [CGFloat] {
            let ring = UIBezierPath(roundedRect: CGRect(x: r.minX + r.width * fx - r.width * 0.03, y: r.minY - r.height * 0.06,
                                                        width: r.width * 0.06, height: r.height * 0.13), cornerRadius: r.width * 0.03)
            withShadow(ctx, blur: 1.5, offset: CGSize(width: 0, height: 1), alpha: 0.4) {
                fill(ctx, ring, [UIColor(white: 0.85, alpha: 1), UIColor(white: 0.35, alpha: 1)], vertical: false)
            }
        }
    }

    static func contactsScene(_ ctx: CGContext, _ b: CGRect) {
        let r = box(b, 0.7, aspect: 1.3)
        scene(ctx, b, icon: r)
        let card = UIBezierPath(roundedRect: r, cornerRadius: r.height * 0.08)
        withShadow(ctx, blur: 5, offset: CGSize(width: 0, height: 2), alpha: 0.35) {
            fill(ctx, card, [rgb(0.62, 0.40, 0.22), rgb(0.40, 0.24, 0.12)])
        }
        let page = UIBezierPath(roundedRect: r.inset(by: UIEdgeInsets(top: r.height * 0.06, left: r.width * 0.12, bottom: r.height * 0.06, right: r.width * 0.06)),
                                cornerRadius: r.height * 0.04)
        fill(ctx, page, [UIColor.white, UIColor(white: 0.92, alpha: 1)])
        let p = page.bounds
        // Index tabs
        let tabColors = [rgb(0.9, 0.3, 0.3), rgb(0.95, 0.7, 0.2), rgb(0.35, 0.7, 0.3), rgb(0.3, 0.55, 0.9)]
        for (i, color) in tabColors.enumerated() {
            let tab = UIBezierPath(roundedRect: CGRect(x: p.maxX - 2, y: p.minY + p.height * (0.1 + CGFloat(i) * 0.2), width: r.width * 0.06, height: p.height * 0.15),
                                   cornerRadius: 2)
            color.setFill()
            tab.fill()
        }
        // Avatar silhouette
        let ad = p.height * 0.5
        let avatar = CGRect(x: p.minX + p.width * 0.1, y: p.midY - ad / 2 - p.height * 0.05, width: ad, height: ad)
        let circle = UIBezierPath(ovalIn: avatar)
        ctx.saveGState()
        ctx.addPath(circle.cgPath)
        ctx.clip()
        gradient(ctx, [rgb(0.75, 0.82, 0.92), rgb(0.50, 0.60, 0.75)], from: CGPoint(x: avatar.midX, y: avatar.minY), to: CGPoint(x: avatar.midX, y: avatar.maxY))
        UIColor(white: 0.97, alpha: 1).setFill()
        ctx.fillEllipse(in: CGRect(x: avatar.midX - ad * 0.19, y: avatar.minY + ad * 0.18, width: ad * 0.38, height: ad * 0.40))
        ctx.fillEllipse(in: CGRect(x: avatar.midX - ad * 0.36, y: avatar.minY + ad * 0.62, width: ad * 0.72, height: ad * 0.6))
        ctx.restoreGState()
        UIColor(white: 0.6, alpha: 1).setStroke()
        circle.lineWidth = 0.75
        circle.stroke()
        // Text lines
        let lx = avatar.maxX + p.width * 0.08
        let lw = p.maxX - lx - p.width * 0.1
        for (i, (frac, shade)) in [(0.9, 0.3), (0.65, 0.65), (0.75, 0.65)].enumerated() {
            UIColor(white: CGFloat(shade), alpha: 1).setFill()
            let h = p.height * (i == 0 ? 0.09 : 0.06)
            ctx.fill(CGRect(x: lx, y: avatar.minY + ad * 0.15 + CGFloat(i) * p.height * 0.16, width: lw * CGFloat(frac), height: h))
        }
        UIColor(white: 0.8, alpha: 1).setFill()
        ctx.fill(CGRect(x: p.minX + p.width * 0.08, y: p.maxY - p.height * 0.14, width: p.width * 0.78, height: 1))
    }

    static func bellScene(_ ctx: CGContext, _ b: CGRect) {
        let r = box(b, 0.56)
        scene(ctx, b, icon: r)
        let u = r.width
        let cx = r.midX
        let top = r.minY + 0.14 * u
        let bottom = r.minY + 0.80 * u
        let bell = UIBezierPath()
        bell.move(to: CGPoint(x: cx - 0.12 * u, y: top))
        bell.addCurve(to: CGPoint(x: cx - 0.36 * u, y: bottom - 0.08 * u),
                      controlPoint1: CGPoint(x: cx - 0.32 * u, y: top + 0.02 * u), controlPoint2: CGPoint(x: cx - 0.28 * u, y: bottom - 0.30 * u))
        bell.addLine(to: CGPoint(x: cx - 0.44 * u, y: bottom))
        bell.addLine(to: CGPoint(x: cx + 0.44 * u, y: bottom))
        bell.addLine(to: CGPoint(x: cx + 0.36 * u, y: bottom - 0.08 * u))
        bell.addCurve(to: CGPoint(x: cx + 0.12 * u, y: top),
                      controlPoint1: CGPoint(x: cx + 0.28 * u, y: bottom - 0.30 * u), controlPoint2: CGPoint(x: cx + 0.32 * u, y: top + 0.02 * u))
        bell.addQuadCurve(to: CGPoint(x: cx - 0.12 * u, y: top), controlPoint: CGPoint(x: cx, y: top - 0.07 * u))
        bell.close()
        let gold = [rgb(0.72, 0.50, 0.08), rgb(1, 0.90, 0.50), rgb(0.92, 0.72, 0.22), rgb(0.62, 0.42, 0.06)]
        let clapper = UIBezierPath(ovalIn: CGRect(x: cx - 0.08 * u, y: bottom - 0.02 * u, width: 0.16 * u, height: 0.14 * u))
        let knob = UIBezierPath(ovalIn: CGRect(x: cx - 0.06 * u, y: top - 0.12 * u, width: 0.12 * u, height: 0.12 * u))
        withShadow(ctx, blur: 5, offset: CGSize(width: 0, height: 2), alpha: 0.4) {
            fill(ctx, clapper, [rgb(0.80, 0.60, 0.20), rgb(0.50, 0.32, 0.05)])
            fill(ctx, knob, gold, vertical: false, locations: [0, 0.35, 0.6, 1])
            fill(ctx, bell, gold, vertical: false, locations: [0, 0.35, 0.6, 1])
        }
        let lip = UIBezierPath(roundedRect: CGRect(x: cx - 0.45 * u, y: bottom - 0.06 * u, width: 0.9 * u, height: 0.07 * u), cornerRadius: 0.03 * u)
        fill(ctx, lip, [rgb(0.95, 0.80, 0.35), rgb(0.60, 0.40, 0.05)])
        gloss(ctx, bell, strength: 0.35)
        // Ringing arcs
        UIColor(white: 0.45, alpha: 0.8).setStroke()
        for side in [-1, 1] as [CGFloat] {
            for k in [0.52, 0.62] as [CGFloat] {
                let start: CGFloat = side < 0 ? .pi * 1.12 : -.pi * 0.36
                let arc = UIBezierPath(arcCenter: CGPoint(x: cx, y: r.minY + 0.45 * u), radius: k * u, startAngle: start, endAngle: start + .pi * 0.24, clockwise: true)
                arc.lineWidth = max(1.5, 0.03 * u)
                arc.lineCapStyle = .round
                arc.stroke()
            }
        }
    }

    static func gamesMontageScene(_ ctx: CGContext, _ b: CGRect) {
        let r = box(b, 0.8, aspect: 1.25)
        softBackground(ctx, b)
        let gap = r.width * 0.05
        let w = (r.width - gap) / 2
        let h = (r.height - gap) / 2
        for (i, name) in ["Brick", "Klondike", "Vortex", "Parachute"].enumerated() {
            let cell = CGRect(x: r.minX + CGFloat(i % 2) * (w + gap), y: r.minY + CGFloat(i / 2) * (h + gap), width: w, height: h)
            gameCard(name, ctx, cell, showTitle: false)
        }
    }

    static func notesScene(_ ctx: CGContext, _ b: CGRect) {
        let r = box(b, 0.7, aspect: 0.8)
        scene(ctx, b, icon: r)
        let page = UIBezierPath(rect: r)
        withShadow(ctx, blur: 5, offset: CGSize(width: 0, height: 2), alpha: 0.35) {
            fill(ctx, page, [rgb(1, 0.98, 0.80), rgb(0.98, 0.92, 0.62)])
        }
        let bindH = r.height * 0.11
        let binding = UIBezierPath(rect: CGRect(x: r.minX, y: r.minY, width: r.width, height: bindH))
        fill(ctx, binding, [rgb(0.55, 0.32, 0.16), rgb(0.33, 0.17, 0.07)])
        gloss(ctx, binding, strength: 0.3)
        ctx.saveGState()
        ctx.setStrokeColor(rgb(0.55, 0.70, 0.90).cgColor)
        ctx.setLineWidth(1)
        let spacing = r.height * 0.1
        var y = r.minY + bindH + spacing
        while y < r.maxY - 2 {
            ctx.move(to: CGPoint(x: r.minX, y: y)); ctx.addLine(to: CGPoint(x: r.maxX, y: y))
            y += spacing
        }
        ctx.strokePath()
        ctx.setStrokeColor(rgb(0.90, 0.40, 0.40).cgColor)
        let mx = r.minX + r.width * 0.16
        ctx.move(to: CGPoint(x: mx, y: r.minY + bindH)); ctx.addLine(to: CGPoint(x: mx, y: r.maxY))
        ctx.strokePath()
        // "Handwriting"
        ctx.setStrokeColor(UIColor(white: 0.3, alpha: 0.85).cgColor)
        ctx.setLineWidth(max(1, r.height * 0.012))
        ctx.setLineCap(.round)
        for (i, frac) in [0.62, 0.48, 0.70, 0.35].enumerated() {
            let ly = r.minY + bindH + spacing * CGFloat(i + 1) - spacing * 0.28
            var x = mx + r.width * 0.06
            let end = x + (r.maxX - x - r.width * 0.06) * CGFloat(frac)
            ctx.move(to: CGPoint(x: x, y: ly))
            var up = true
            while x < end {
                x += r.width * 0.035
                ctx.addQuadCurve(to: CGPoint(x: min(x, end), y: ly), control: CGPoint(x: x - r.width * 0.0175, y: ly + (up ? -1 : 1) * spacing * 0.22))
                up.toggle()
            }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func padlockScene(_ ctx: CGContext, _ b: CGRect) {
        let r = box(b, 0.58)
        scene(ctx, b, icon: r)
        let u = r.width
        let cx = r.midX
        let bodyTop = r.minY + 0.46 * u
        let arcY = r.minY + 0.30 * u
        let shackle = UIBezierPath()
        shackle.move(to: CGPoint(x: cx - 0.24 * u, y: bodyTop + 0.02 * u))
        shackle.addLine(to: CGPoint(x: cx - 0.24 * u, y: arcY))
        shackle.addArc(withCenter: CGPoint(x: cx, y: arcY), radius: 0.24 * u, startAngle: .pi, endAngle: 0, clockwise: true)
        shackle.addLine(to: CGPoint(x: cx + 0.24 * u, y: bodyTop + 0.02 * u))
        withShadow(ctx, blur: 3, offset: CGSize(width: 0, height: 1), alpha: 0.35) {
            ctx.saveGState()
            ctx.addPath(shackle.cgPath)
            ctx.setLineWidth(0.09 * u)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            gradient(ctx, [UIColor(white: 0.55, alpha: 1), UIColor(white: 0.98, alpha: 1), UIColor(white: 0.6, alpha: 1),
                           UIColor(white: 0.95, alpha: 1), UIColor(white: 0.5, alpha: 1)],
                     from: CGPoint(x: cx - 0.3 * u, y: 0), to: CGPoint(x: cx + 0.3 * u, y: 0))
            ctx.restoreGState()
        }
        let body = UIBezierPath(roundedRect: CGRect(x: cx - 0.36 * u, y: bodyTop, width: 0.72 * u, height: 0.5 * u), cornerRadius: 0.08 * u)
        withShadow(ctx, blur: 5, offset: CGSize(width: 0, height: 2), alpha: 0.4) {
            fill(ctx, body, [rgb(1, 0.87, 0.45), rgb(0.88, 0.66, 0.18), rgb(0.70, 0.48, 0.08)])
        }
        gloss(ctx, body, strength: 0.45)
        let hole = UIBezierPath(ovalIn: CGRect(x: cx - 0.06 * u, y: bodyTop + 0.13 * u, width: 0.12 * u, height: 0.12 * u))
        hole.move(to: CGPoint(x: cx - 0.03 * u, y: bodyTop + 0.22 * u))
        hole.addLine(to: CGPoint(x: cx - 0.045 * u, y: bodyTop + 0.36 * u))
        hole.addLine(to: CGPoint(x: cx + 0.045 * u, y: bodyTop + 0.36 * u))
        hole.addLine(to: CGPoint(x: cx + 0.03 * u, y: bodyTop + 0.22 * u))
        hole.close()
        UIColor(white: 0.18, alpha: 1).setFill()
        hole.fill()
        UIColor(red: 0.55, green: 0.38, blue: 0.05, alpha: 0.7).setStroke()
        body.lineWidth = 0.75
        body.stroke()
    }

    static func stopwatchScene(_ ctx: CGContext, _ b: CGRect) {
        let r = box(b, 0.62)
        scene(ctx, b, icon: r)
        let u = r.width
        let R = 0.42 * u
        let c = CGPoint(x: r.midX, y: r.minY + 0.56 * u)
        let chrome = [UIColor(white: 0.98, alpha: 1), UIColor(white: 0.62, alpha: 1), UIColor(white: 0.9, alpha: 1), UIColor(white: 0.5, alpha: 1)]
        withShadow(ctx, blur: 5, offset: CGSize(width: 0, height: 2), alpha: 0.4) {
            let stem = UIBezierPath(rect: CGRect(x: c.x - 0.045 * u, y: c.y - R - 0.1 * u, width: 0.09 * u, height: 0.12 * u))
            fill(ctx, stem, chrome, vertical: false)
            let crown = UIBezierPath(roundedRect: CGRect(x: c.x - 0.1 * u, y: c.y - R - 0.16 * u, width: 0.2 * u, height: 0.07 * u), cornerRadius: 0.025 * u)
            fill(ctx, crown, chrome, vertical: false)
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            ctx.rotate(by: .pi / 4)
            let side = UIBezierPath(roundedRect: CGRect(x: -0.04 * u, y: -R - 0.09 * u, width: 0.08 * u, height: 0.1 * u), cornerRadius: 0.02 * u)
            fill(ctx, side, chrome, vertical: false)
            ctx.restoreGState()
            fill(ctx, UIBezierPath(ovalIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2)), chrome, locations: [0, 0.45, 0.7, 1])
        }
        fill(ctx, UIBezierPath(ovalIn: CGRect(x: c.x - R * 0.88, y: c.y - R * 0.88, width: R * 1.76, height: R * 1.76)),
             [UIColor(white: 0.45, alpha: 1), UIColor(white: 0.88, alpha: 1)])
        let face = UIBezierPath(ovalIn: CGRect(x: c.x - R * 0.82, y: c.y - R * 0.82, width: R * 1.64, height: R * 1.64))
        fill(ctx, face, [UIColor.white, UIColor(white: 0.9, alpha: 1)])
        ctx.saveGState()
        ctx.setStrokeColor(UIColor(white: 0.2, alpha: 1).cgColor)
        for i in 0..<60 {
            let a = CGFloat(i) / 60 * 2 * .pi - .pi / 2
            let major = i % 5 == 0
            let r0 = R * (major ? 0.64 : 0.72)
            ctx.setLineWidth(major ? max(1, R * 0.03) : 0.6)
            ctx.move(to: CGPoint(x: c.x + cos(a) * r0, y: c.y + sin(a) * r0))
            ctx.addLine(to: CGPoint(x: c.x + cos(a) * R * 0.78, y: c.y + sin(a) * R * 0.78))
            ctx.strokePath()
        }
        ctx.setLineWidth(0.75)
        ctx.setStrokeColor(UIColor(white: 0.55, alpha: 1).cgColor)
        ctx.strokeEllipse(in: CGRect(x: c.x - R * 0.18, y: c.y + R * 0.2, width: R * 0.36, height: R * 0.36))
        let a = 2 * CGFloat.pi * 10 / 60 - .pi / 2
        ctx.setStrokeColor(rgb(0.85, 0.1, 0.08).cgColor)
        ctx.setLineWidth(max(1.2, R * 0.035))
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: c.x - cos(a) * R * 0.16, y: c.y - sin(a) * R * 0.16))
        ctx.addLine(to: CGPoint(x: c.x + cos(a) * R * 0.74, y: c.y + sin(a) * R * 0.74))
        ctx.strokePath()
        ctx.setFillColor(rgb(0.6, 0.05, 0.05).cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - R * 0.06, y: c.y - R * 0.06, width: R * 0.12, height: R * 0.12))
        ctx.restoreGState()
        gloss(ctx, face, strength: 0.35)
    }

    // MARK: Games

    static func gameScene(_ name: String, _ ctx: CGContext, _ b: CGRect) {
        let r = box(b, 0.8, aspect: 1.2)
        scene(ctx, b, icon: r)
        gameCard(name, ctx, r, showTitle: true)
    }

    static func gameCard(_ name: String, _ ctx: CGContext, _ r: CGRect, showTitle: Bool) {
        let path = UIBezierPath(roundedRect: r, cornerRadius: min(r.width, r.height) * 0.08)
        withShadow(ctx, blur: 5, offset: CGSize(width: 0, height: 2), alpha: 0.4) {
            UIColor.black.setFill()
            path.fill()
        }
        ctx.saveGState()
        ctx.addPath(path.cgPath)
        ctx.clip()
        gameArt(name, ctx, r)
        if showTitle {
            let band = CGRect(x: r.minX, y: r.maxY - r.height * 0.26, width: r.width, height: r.height * 0.26)
            gradient(ctx, [UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0.8)],
                     from: CGPoint(x: band.midX, y: band.minY), to: CGPoint(x: band.midX, y: band.maxY))
            withShadow(ctx, blur: 2, offset: CGSize(width: 0, height: 1), alpha: 0.8) {
                text(name, band.insetBy(dx: 6, dy: 0).offsetBy(dx: 0, dy: band.height * 0.1),
                     size: min(band.height * 0.48, 16), color: .white)
            }
        }
        ctx.restoreGState()
        gloss(ctx, path, strength: 0.28)
        UIColor(white: 1, alpha: 0.35).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private static func bg(_ ctx: CGContext, _ r: CGRect, _ top: UIColor, _ bottom: UIColor) {
        gradient(ctx, [top, bottom], from: CGPoint(x: r.midX, y: r.minY), to: CGPoint(x: r.midX, y: r.maxY))
    }

    private static func block(_ ctx: CGContext, _ rect: CGRect, _ color: UIColor) {
        let p = UIBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        color.setFill()
        p.fill()
        gloss(ctx, p, strength: 0.45)
        UIColor(white: 0, alpha: 0.35).setStroke()
        p.lineWidth = 0.5
        p.stroke()
    }

    static func playingCard(_ ctx: CGContext, center: CGPoint, height h: CGFloat, angle: CGFloat, rank: String, suit: String, red: Bool) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: angle)
        let w = h * 0.7
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        let card = UIBezierPath(roundedRect: rect, cornerRadius: w * 0.1)
        withShadow(ctx, blur: 3, offset: CGSize(width: 1, height: 2), alpha: 0.45) {
            fill(ctx, card, [UIColor.white, UIColor(white: 0.92, alpha: 1)])
        }
        UIColor(white: 0.6, alpha: 1).setStroke()
        card.lineWidth = 0.5
        card.stroke()
        let color = red ? rgb(0.82, 0.08, 0.08) : UIColor(white: 0.08, alpha: 1)
        text(rank, CGRect(x: rect.minX + w * 0.08, y: rect.minY + h * 0.04, width: w * 0.35, height: h * 0.2), size: h * 0.18, color: color, align: .left)
        text(suit, CGRect(x: rect.minX, y: rect.minY + h * 0.2, width: w, height: h * 0.7), size: h * 0.42, color: color)
        ctx.restoreGState()
    }

    static func gameArt(_ name: String, _ ctx: CGContext, _ r: CGRect) {
        let w = r.width, h = r.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * w, y: r.minY + y * h) }
        switch name {
        case "Blocks":
            bg(ctx, r, rgb(0.10, 0.12, 0.30), rgb(0.02, 0.03, 0.10))
            let cell = h / 8
            let cols = Int(w / cell)
            let ox = r.minX + (w - CGFloat(cols) * cell) / 2
            func at(_ c: Int, _ row: Int) -> CGRect { CGRect(x: ox + CGFloat(c) * cell, y: r.maxY - CGFloat(row + 1) * cell, width: cell, height: cell) }
            let palette = [rgb(0.2, 0.8, 0.9), rgb(0.95, 0.85, 0.2), rgb(0.6, 0.3, 0.85), rgb(0.3, 0.8, 0.3), rgb(0.9, 0.25, 0.2), rgb(0.95, 0.55, 0.15), rgb(0.25, 0.4, 0.9)]
            for c in 0..<cols where c != cols - 3 { block(ctx, at(c, 0), palette[(c / 2) % palette.count]) }
            for c in 0..<cols where c % 4 != 3 && c != cols - 3 { block(ctx, at(c, 1), palette[(c / 3 + 3) % palette.count]) }
            let m = cols / 2
            for (c, row) in [(m - 1, 5), (m, 5), (m + 1, 5), (m, 4)] { block(ctx, at(c, row), palette[2]) }
        case "Brick":
            bg(ctx, r, UIColor(white: 0.14, alpha: 1), UIColor(white: 0.02, alpha: 1))
            let colors = [rgb(0.9, 0.2, 0.2), rgb(0.95, 0.55, 0.15), rgb(0.95, 0.85, 0.2), rgb(0.3, 0.8, 0.3)]
            let bw = w / 6, bh = h * 0.08
            for (row, color) in colors.enumerated() {
                for c in 0..<6 where !(row == 1 && c == 2) && !(row == 3 && (c == 4 || c == 1)) {
                    block(ctx, CGRect(x: r.minX + CGFloat(c) * bw, y: r.minY + h * 0.1 + CGFloat(row) * bh, width: bw, height: bh).insetBy(dx: 0.5, dy: 0.5), color)
                }
            }
            let paddle = UIBezierPath(roundedRect: CGRect(x: r.minX + w * 0.40, y: r.minY + h * 0.66, width: w * 0.28, height: h * 0.05), cornerRadius: h * 0.025)
            fill(ctx, paddle, [UIColor.white, UIColor(white: 0.6, alpha: 1)])
            let d = min(w, h) * 0.06
            UIColor.white.setFill()
            ctx.fillEllipse(in: CGRect(x: p(0.62, 0.5).x, y: p(0.62, 0.5).y, width: d, height: d))
        case "iQuiz":
            bg(ctx, r, rgb(0.40, 0.65, 0.98), rgb(0.10, 0.30, 0.75))
            withShadow(ctx, blur: 3, offset: CGSize(width: 0, height: 2), alpha: 0.5) {
                text("?", CGRect(x: r.minX, y: r.minY, width: w, height: h * 0.78), size: h * 0.6, color: .white)
            }
        case "Klondike":
            bg(ctx, r, rgb(0.15, 0.55, 0.25), rgb(0.04, 0.32, 0.12))
            let ch = h * 0.6
            playingCard(ctx, center: p(0.40, 0.40), height: ch, angle: -0.22, rank: "A", suit: "♠", red: false)
            playingCard(ctx, center: p(0.60, 0.42), height: ch, angle: 0.16, rank: "K", suit: "♥", red: true)
        case "Maze":
            bg(ctx, r, UIColor(white: 0.97, alpha: 1), UIColor(white: 0.82, alpha: 1))
            let area = CGRect(x: r.minX + w * 0.1, y: r.minY + h * 0.08, width: w * 0.8, height: h * 0.62)
            let cw = area.width / 6, chh = area.height / 4
            func g(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: area.minX + x * cw, y: area.minY + y * chh) }
            ctx.saveGState()
            ctx.setStrokeColor(UIColor(white: 0.2, alpha: 1).cgColor)
            ctx.setLineWidth(max(1.5, w * 0.015))
            ctx.setLineCap(.square)
            ctx.stroke(area)
            let walls: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(1, 0, 1, 3), (2, 1, 2, 4), (3, 0, 3, 2), (4, 1, 4, 3), (5, 0, 5, 1), (3, 3, 5, 3), (5, 2, 6, 2), (2, 1, 3, 1)]
            for (x1, y1, x2, y2) in walls {
                ctx.move(to: g(x1, y1)); ctx.addLine(to: g(x2, y2))
            }
            ctx.strokePath()
            ctx.restoreGState()
            let d = min(cw, chh) * 0.55
            rgb(0.85, 0.15, 0.1).setFill()
            ctx.fillEllipse(in: CGRect(x: g(0.5, 0.5).x - d / 2, y: g(0.5, 0.5).y - d / 2, width: d, height: d))
            rgb(0.2, 0.7, 0.25).setFill()
            ctx.fill(CGRect(x: g(5.5, 3.5).x - d / 2, y: g(5.5, 3.5).y - d / 2, width: d, height: d))
        case "Minesweeper":
            bg(ctx, r, UIColor(white: 0.78, alpha: 1), UIColor(white: 0.62, alpha: 1))
            let cols = 6, rows = 4
            let area = CGRect(x: r.minX + w * 0.06, y: r.minY + h * 0.06, width: w * 0.88, height: h * 0.66)
            let cw = area.width / CGFloat(cols), chh = area.height / CGFloat(rows)
            let open: [Int: String] = [7: "1", 8: "1", 9: "2", 13: "1", 14: "", 15: "3", 19: "1", 20: "2"]
            for row in 0..<rows {
                for c in 0..<cols {
                    let i = row * cols + c
                    let cell = CGRect(x: area.minX + CGFloat(c) * cw, y: area.minY + CGFloat(row) * chh, width: cw, height: chh)
                    if i == 10 {
                        rgb(0.9, 0.2, 0.2).setFill(); ctx.fill(cell)
                        let d = min(cw, chh) * 0.5
                        UIColor.black.setFill()
                        ctx.fillEllipse(in: CGRect(x: cell.midX - d / 2, y: cell.midY - d / 2, width: d, height: d))
                    } else if let n = open[i] {
                        UIColor(white: 0.70, alpha: 1).setFill(); ctx.fill(cell)
                        UIColor(white: 0.55, alpha: 1).setStroke(); ctx.setLineWidth(0.5); ctx.stroke(cell)
                        let color = n == "1" ? rgb(0.1, 0.2, 0.85) : n == "2" ? rgb(0.1, 0.55, 0.1) : rgb(0.85, 0.1, 0.1)
                        if !n.isEmpty { text(n, cell, size: chh * 0.62, color: color) }
                    } else {
                        UIColor(white: 0.82, alpha: 1).setFill(); ctx.fill(cell)
                        UIColor.white.setFill()
                        ctx.fill(CGRect(x: cell.minX, y: cell.minY, width: cell.width, height: 1.5))
                        ctx.fill(CGRect(x: cell.minX, y: cell.minY, width: 1.5, height: cell.height))
                        UIColor(white: 0.45, alpha: 1).setFill()
                        ctx.fill(CGRect(x: cell.minX, y: cell.maxY - 1.5, width: cell.width, height: 1.5))
                        ctx.fill(CGRect(x: cell.maxX - 1.5, y: cell.minY, width: 1.5, height: cell.height))
                        if i == 4 {
                            let flag = UIBezierPath()
                            flag.move(to: CGPoint(x: cell.midX - cw * 0.05, y: cell.minY + chh * 0.2))
                            flag.addLine(to: CGPoint(x: cell.midX + cw * 0.25, y: cell.minY + chh * 0.35))
                            flag.addLine(to: CGPoint(x: cell.midX - cw * 0.05, y: cell.minY + chh * 0.5))
                            flag.close()
                            rgb(0.9, 0.1, 0.1).setFill(); flag.fill()
                            UIColor.black.setFill()
                            ctx.fill(CGRect(x: cell.midX - cw * 0.07, y: cell.minY + chh * 0.2, width: 1.2, height: chh * 0.6))
                        }
                    }
                }
            }
        case "Music Quiz":
            bg(ctx, r, rgb(0.70, 0.40, 0.90), rgb(0.35, 0.12, 0.55))
            let s = min(w * 0.42, h * 0.62)
            withShadow(ctx, blur: 3, offset: CGSize(width: 0, height: 2), alpha: 0.5) {
                musicNote(ctx, CGRect(x: r.midX - s * 1.0, y: r.minY + h * 0.08, width: s, height: s), color: .white)
                text("?", CGRect(x: r.midX, y: r.minY, width: w * 0.4, height: h * 0.78), size: h * 0.5, color: .white)
            }
        case "Parachute":
            bg(ctx, r, rgb(0.50, 0.75, 0.98), rgb(0.85, 0.94, 1))
            rgb(0.35, 0.65, 0.25).setFill()
            ctx.fill(CGRect(x: r.minX, y: r.minY + h * 0.68, width: w, height: h * 0.32))
            // Turret
            UIColor(white: 0.3, alpha: 1).setFill()
            ctx.fill(CGRect(x: r.midX - w * 0.05, y: r.minY + h * 0.6, width: w * 0.1, height: h * 0.08))
            ctx.saveGState()
            ctx.setStrokeColor(UIColor(white: 0.3, alpha: 1).cgColor)
            ctx.setLineWidth(max(1.5, w * 0.02))
            ctx.move(to: p(0.5, 0.6)); ctx.addLine(to: p(0.56, 0.48))
            ctx.strokePath()
            // Helicopter
            let dark = UIColor(white: 0.2, alpha: 1)
            dark.setFill(); dark.setStroke()
            ctx.fillEllipse(in: CGRect(x: p(0.24, 0.18).x, y: p(0.24, 0.18).y, width: w * 0.2, height: h * 0.12))
            ctx.setLineWidth(max(1.5, h * 0.025))
            ctx.move(to: p(0.26, 0.23)); ctx.addLine(to: p(0.08, 0.21))
            ctx.move(to: p(0.08, 0.15)); ctx.addLine(to: p(0.08, 0.27))
            ctx.move(to: p(0.34, 0.18)); ctx.addLine(to: p(0.34, 0.14))
            ctx.move(to: p(0.18, 0.14)); ctx.addLine(to: p(0.50, 0.14))
            ctx.move(to: p(0.26, 0.33)); ctx.addLine(to: p(0.44, 0.33))
            ctx.strokePath()
            // Parachutist
            let cc = p(0.74, 0.30)
            let cr = w * 0.1
            let canopy = UIBezierPath(arcCenter: cc, radius: cr, startAngle: .pi, endAngle: 0, clockwise: true)
            canopy.close()
            fill(ctx, canopy, [rgb(0.95, 0.3, 0.25), rgb(0.75, 0.1, 0.1)])
            ctx.setLineWidth(0.75)
            let body = p(0.74, 0.46)
            ctx.move(to: CGPoint(x: cc.x - cr, y: cc.y)); ctx.addLine(to: body)
            ctx.move(to: CGPoint(x: cc.x + cr, y: cc.y)); ctx.addLine(to: body)
            ctx.strokePath()
            ctx.setLineWidth(max(1.5, w * 0.015))
            ctx.move(to: body); ctx.addLine(to: CGPoint(x: body.x, y: body.y + h * 0.08))
            ctx.strokePath()
            ctx.fillEllipse(in: CGRect(x: body.x - w * 0.018, y: body.y - w * 0.03, width: w * 0.036, height: w * 0.036))
            ctx.restoreGState()
        case "Snake":
            bg(ctx, r, rgb(0.78, 0.86, 0.58), rgb(0.60, 0.72, 0.40))
            let cell = h / 9
            let cols = Int(w / cell)
            let ox = r.minX + (w - CGFloat(cols) * cell) / 2
            func at(_ c: Int, _ row: Int) -> CGRect { CGRect(x: ox + CGFloat(c) * cell, y: r.minY + CGFloat(row) * cell, width: cell, height: cell).insetBy(dx: 0.6, dy: 0.6) }
            let body = [(2, 5), (3, 5), (4, 5), (5, 5), (5, 4), (5, 3), (6, 3), (7, 3), (8, 3), (9, 3)]
            UIColor(white: 0.12, alpha: 1).setFill()
            for (c, row) in body where c < cols { ctx.fill(at(c, row)) }
            let food = at(min(cols - 2, 12), 2)
            rgb(0.8, 0.1, 0.1).setFill()
            ctx.fillEllipse(in: food)
        case "Vortex":
            bg(ctx, r, rgb(0.05, 0.02, 0.15), UIColor.black)
            let c = p(0.5, 0.40)
            ctx.saveGState()
            for k in 0..<7 {
                let t = CGFloat(k) / 6
                let rx = w * 0.46 * (1 - t * 0.85)
                let ry = h * 0.34 * (1 - t * 0.85)
                let cy = c.y - t * h * 0.08
                UIColor(hue: 0.52 + t * 0.25, saturation: 0.8, brightness: 1, alpha: 1 - t * 0.6).setStroke()
                ctx.setLineWidth(2 * (1 - t) + 0.5)
                ctx.strokeEllipse(in: CGRect(x: c.x - rx, y: cy - ry, width: rx * 2, height: ry * 2))
            }
            let rx = w * 0.46, ry = h * 0.34
            let arc = UIBezierPath(arcCenter: .zero, radius: rx, startAngle: .pi * 0.35, endAngle: .pi * 0.65, clockwise: true)
            arc.apply(CGAffineTransform(scaleX: 1, y: ry / rx).concatenating(CGAffineTransform(translationX: c.x, y: c.y)))
            arc.lineWidth = max(3, h * 0.05)
            arc.lineCapStyle = .round
            rgb(1, 0.6, 0.15).setStroke()
            arc.stroke()
            let d = min(w, h) * 0.06
            UIColor.white.setFill()
            ctx.fillEllipse(in: CGRect(x: c.x + rx * 0.2 - d / 2, y: c.y + ry * 0.45 - d / 2, width: d, height: d))
            ctx.restoreGState()
        default:
            bg(ctx, r, UIColor.gradientLightBlue, UIColor.gradientDarkBlue)
            text(String(name.prefix(1)), CGRect(x: r.minX, y: r.minY, width: w, height: h * 0.78), size: h * 0.5, color: .white)
        }
    }
}

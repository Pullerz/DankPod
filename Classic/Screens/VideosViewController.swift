//
//  VideosViewController.swift
//  Classic
//

import UIKit
import MediaPlayer

/// One of the iPod's video categories, backed by an MPMediaQuery on the media type.
struct VideoCategory {
    let title: String
    let mediaType: MPMediaType

    static let all: [VideoCategory] = [
        VideoCategory(title: "Movies", mediaType: .movie),
        VideoCategory(title: "Music Videos", mediaType: .musicVideo),
        VideoCategory(title: "TV Shows", mediaType: .tvShow),
        VideoCategory(title: "Video Podcasts", mediaType: .videoPodcast),
    ]

    func items() -> [MPMediaItem] {
        let predicate = MPMediaPropertyPredicate(value: NSNumber(value: mediaType.rawValue),
                                                 forProperty: MPMediaItemPropertyMediaType,
                                                 comparisonType: .equalTo)
        let items = MPMediaQuery(filterPredicates: [predicate]).items ?? []
        return items.sorted {
            ($0.title ?? "").localizedCaseInsensitiveCompare($1.title ?? "") == .orderedAscending
        }
    }
}

/// Builds a centred iPod-style empty-state message ("No Videos").
func makePodEmptyStateView(title: String, subtitle: String?) -> UIView {
    let container = UIView()
    container.backgroundColor = .white
    let stack = UIStackView()
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 6
    stack.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(stack)
    stack.centerXAnchor.constraint(equalTo: container.centerXAnchor).isActive = true
    stack.centerYAnchor.constraint(equalTo: container.centerYAnchor).isActive = true
    stack.leftAnchor.constraint(greaterThanOrEqualTo: container.leftAnchor, constant: 20).isActive = true
    stack.rightAnchor.constraint(lessThanOrEqualTo: container.rightAnchor, constant: -20).isActive = true

    let titleLabel = UILabel()
    titleLabel.font = UIFont(name: "Helvetica-Bold", size: 20)
    titleLabel.textColor = .black
    titleLabel.text = title
    titleLabel.textAlignment = .center
    stack.addArrangedSubview(titleLabel)

    if let subtitle = subtitle {
        let sub = UILabel()
        sub.font = UIFont(name: "Helvetica", size: 13)
        sub.textColor = UIColor(white: 0.4, alpha: 1)
        sub.text = subtitle
        sub.numberOfLines = 0
        sub.textAlignment = .center
        stack.addArrangedSubview(sub)
    }
    return container
}

// MARK: - Videos (category list)

class VideosViewController: UIViewController, ClickWheelProtocol {
    private var categories: [(category: VideoCategory, items: [MPMediaItem])] = []
    let tableView = UITableView()
    private let emptyView = makePodEmptyStateView(title: "No Videos",
                                                  subtitle: "Add movies, music videos, TV shows or video podcasts to your library.")
    var counter = 0
    private var hasSetupUI = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Videos"
        reloadCategories()
    }

    private func setupUI() {
        guard !hasSetupUI else { return }
        hasSetupUI = true
        view.backgroundColor = .white
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        tableView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        tableView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        tableView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none

        emptyView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyView)
        emptyView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        emptyView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        emptyView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        emptyView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        emptyView.isHidden = true
    }

    /// Re-queries the library each time so newly synced videos appear; empty categories are hidden.
    private func reloadCategories() {
        let previousTitle = counter < categories.count ? categories[counter].category.title : nil
        categories = VideoCategory.all.compactMap { category in
            let items = category.items()
            return items.isEmpty ? nil : (category, items)
        }
        if let previousTitle = previousTitle,
           let index = categories.firstIndex(where: { $0.category.title == previousTitle }) {
            counter = index
        }
        counter = min(max(counter, 0), max(categories.count - 1, 0))
        emptyView.isHidden = !categories.isEmpty
        tableView.isHidden = categories.isEmpty
        tableView.reloadData()
        if !categories.isEmpty {
            tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .none)
        }
    }

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        guard !categories.isEmpty else { return }
        if rotationDirection == .CLOCKWISE {
            if counter + 1 <= categories.count - 1 { counter += 1 }
        } else if counter > 0 {
            counter -= 1
        }
        let ip = IndexPath(row: counter, section: 0)
        tableView.selectRow(at: ip, animated: false, scrollPosition: .none)
        tableView.scrollToRow(at: ip, at: .none, animated: false)
    }

    func playPausePressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            AppDelegate.music.playPause()
        }
    }

    func nextSongPressed(pressure: ClickWheelTouchPressure) {}

    func previousSongPressed(pressure: ClickWheelTouchPressure) {}

    func menuPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            navigationController?.popViewController(animated: true)
        } else if pressure == .FORCE {
            navigationController?.popToRootViewController(animated: true)
        }
    }

    func centerPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL, counter < categories.count else { return }
        let entry = categories[counter]
        let vc = VideoListViewController(category: entry.category, items: entry.items)
        navigationController?.pushViewController(vc, animated: true)
    }
}

extension VideosViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        categories.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomTableViewCell()
        cell.label.text = categories[indexPath.row].category.title
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        30
    }
}

// MARK: - Video list (items in one category)

class VideoListViewController: UIViewController, ClickWheelProtocol {
    let category: VideoCategory
    private var items: [MPMediaItem]
    let tableView = UITableView()
    private let emptyView = makePodEmptyStateView(title: "No Videos", subtitle: nil)
    var counter = 0
    private var hasSetupUI = false
    private var hasAppearedOnce = false
    private var thumbnailCache: [MPMediaEntityPersistentID: UIImage] = [:]

    init(category: VideoCategory, items: [MPMediaItem]) {
        self.category = category
        self.items = items
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = category.title
        if hasAppearedOnce {
            // Returning from the player: refresh in case the library changed, keeping the selection.
            let selectedID = counter < items.count ? items[counter].persistentID : nil
            items = category.items()
            if let selectedID = selectedID, let index = items.firstIndex(where: { $0.persistentID == selectedID }) {
                counter = index
            }
        }
        hasAppearedOnce = true
        counter = min(max(counter, 0), max(items.count - 1, 0))
        emptyView.isHidden = !items.isEmpty
        tableView.isHidden = items.isEmpty
        tableView.reloadData()
        if !items.isEmpty {
            let ip = IndexPath(row: counter, section: 0)
            tableView.selectRow(at: ip, animated: false, scrollPosition: .none)
            tableView.scrollToRow(at: ip, at: .none, animated: false)
        }
    }

    private func setupUI() {
        guard !hasSetupUI else { return }
        hasSetupUI = true
        view.backgroundColor = .white
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        tableView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        tableView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        tableView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none

        emptyView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyView)
        emptyView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        emptyView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        emptyView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        emptyView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        emptyView.isHidden = true
    }

    fileprivate func thumbnail(for item: MPMediaItem) -> UIImage? {
        if let cached = thumbnailCache[item.persistentID] { return cached }
        guard let image = item.artwork?.image(at: CGSize(width: 96, height: 64)) else { return nil }
        thumbnailCache[item.persistentID] = image
        return image
    }

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        guard !items.isEmpty else { return }
        if rotationDirection == .CLOCKWISE {
            if counter + 1 <= items.count - 1 { counter += 1 }
        } else if counter > 0 {
            counter -= 1
        }
        let ip = IndexPath(row: counter, section: 0)
        tableView.selectRow(at: ip, animated: false, scrollPosition: .none)
        tableView.scrollToRow(at: ip, at: .none, animated: false)
    }

    func playPausePressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            AppDelegate.music.playPause()
        }
    }

    func nextSongPressed(pressure: ClickWheelTouchPressure) {}

    func previousSongPressed(pressure: ClickWheelTouchPressure) {}

    func menuPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            navigationController?.popViewController(animated: true)
        } else if pressure == .FORCE {
            navigationController?.popToRootViewController(animated: true)
        }
    }

    func centerPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL, counter < items.count else { return }
        navigationController?.pushViewController(VideoPlayerViewController(item: items[counter]), animated: true)
    }
}

extension VideoListViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.row]
        let cell = VideoItemCell()
        cell.label.text = item.title ?? "Untitled"
        cell.durationLabel.text = formatVideoTime(item.playbackDuration)
        cell.thumbnailView.image = thumbnail(for: item) ?? VideoItemCell.placeholderThumbnail
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        VideoItemCell.rowHeight
    }
}

/// Formats seconds as m:ss or h:mm:ss.
func formatVideoTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds.rounded(.down))
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

/// A CustomTableViewCell with a thumbnail on the left and a duration on the right; keeps the iPod
/// selection gradient, chevron and Helvetica-Bold title from the base cell.
final class VideoItemCell: CustomTableViewCell {
    static let rowHeight: CGFloat = 44

    let thumbnailView = UIImageView()
    let durationLabel = UILabel()

    /// Drawn "film" placeholder for videos without artwork.
    static let placeholderThumbnail: UIImage = {
        let size = CGSize(width: 48, height: 32)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let colors = [UIColor(white: 0.35, alpha: 1).cgColor, UIColor(white: 0.08, alpha: 1).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            // Sprocket holes along the top and bottom edges.
            UIColor(white: 0.85, alpha: 0.8).setFill()
            var x: CGFloat = 3
            while x < size.width - 3 {
                UIBezierPath(rect: CGRect(x: x, y: 2, width: 3, height: 2)).fill()
                UIBezierPath(rect: CGRect(x: x, y: size.height - 4, width: 3, height: 2)).fill()
                x += 6
            }
            // Play triangle.
            let tri = UIBezierPath()
            tri.move(to: CGPoint(x: rect.midX - 5, y: rect.midY - 7))
            tri.addLine(to: CGPoint(x: rect.midX + 7, y: rect.midY))
            tri.addLine(to: CGPoint(x: rect.midX - 5, y: rect.midY + 7))
            tri.close()
            UIColor.white.setFill()
            tri.fill()
        }
    }()

    override init() {
        super.init()
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.borderColor = UIColor(white: 0, alpha: 0.35).cgColor
        thumbnailView.layer.borderWidth = 0.5
        contentView.addSubview(thumbnailView)
        thumbnailView.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 8).isActive = true
        thumbnailView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true
        thumbnailView.widthAnchor.constraint(equalToConstant: 48).isActive = true
        thumbnailView.heightAnchor.constraint(equalToConstant: 32).isActive = true

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = UIFont(name: "Helvetica", size: 13)
        durationLabel.textColor = UIColor(white: 0.35, alpha: 1)
        durationLabel.textAlignment = .right
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        contentView.addSubview(durationLabel)
        durationLabel.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -6).isActive = true
        durationLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true

        // Re-anchor the base cell's title between the thumbnail and the duration.
        let titleConstraints = contentView.constraints.filter {
            ($0.firstItem as? UILabel) === label && ($0.firstAttribute == .left || $0.firstAttribute == .right)
        }
        NSLayoutConstraint.deactivate(titleConstraints)
        label.leftAnchor.constraint(equalTo: thumbnailView.rightAnchor, constant: 10).isActive = true
        label.rightAnchor.constraint(lessThanOrEqualTo: durationLabel.leftAnchor, constant: -8).isActive = true
        label.lineBreakMode = .byTruncatingTail
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        durationLabel.textColor = selected ? .white : UIColor(white: 0.35, alpha: 1)
    }
}

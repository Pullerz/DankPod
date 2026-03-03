//
//  SearchViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 03/03/2026.
//  Copyright © 2026 Apullen Developments Ltd. All rights reserved.
//

import UIKit
import MediaPlayer

class SearchViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate, UIScrollViewDelegate {

    let searchField = UITextField()
    let tableView = UITableView()
    let emptyLabel = UILabel()

    var songResults: [MPMediaItem] = []
    var artistResults: [String] = []
    var albumResults: [MPMediaItemCollection] = []

    var searchTimer: Timer?
    var hasSetupUI = false

    // Computed section mapping — only include non-empty result types
    private enum SectionType {
        case songs, artists, albums
    }

    private var visibleSections: [SectionType] {
        var sections: [SectionType] = []
        if !songResults.isEmpty { sections.append(.songs) }
        if !artistResults.isEmpty { sections.append(.artists) }
        if !albumResults.isEmpty { sections.append(.albums) }
        return sections
    }

    // Cache visible sections to avoid data inconsistency during table updates
    private var cachedVisibleSections: [SectionType] = []

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.navBarTitle = "Search"
        AppDelegate.baseVC.setClickWheelHidden(true, animated: true)
        searchField.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        searchField.resignFirstResponder()
        AppDelegate.baseVC.setClickWheelHidden(false, animated: true)
    }

    func setupUI() {
        if !hasSetupUI {
            view.backgroundColor = .white

            // Search field
            searchField.translatesAutoresizingMaskIntoConstraints = false
            searchField.placeholder = "Search"
            searchField.font = UIFont(name: "Helvetica", size: 15)
            searchField.borderStyle = .none
            searchField.backgroundColor = UIColor(red: 240/255, green: 240/255, blue: 240/255, alpha: 1)
            searchField.layer.cornerRadius = 8
            searchField.clipsToBounds = true
            searchField.returnKeyType = .search
            searchField.clearButtonMode = .whileEditing
            searchField.autocorrectionType = .no
            searchField.autocapitalizationType = .none
            searchField.delegate = self

            // Left view — magnifying glass icon
            let iconContainer = UIView(frame: CGRect(x: 0, y: 0, width: 30, height: 20))
            let iconView = UIImageView(frame: CGRect(x: 8, y: 0, width: 16, height: 16))
            iconView.center.y = iconContainer.center.y
            if #available(iOS 13.0, *) {
                iconView.image = UIImage(systemName: "magnifyingglass")
            }
            iconView.tintColor = .gray
            iconView.contentMode = .scaleAspectFit
            iconContainer.addSubview(iconView)
            searchField.leftView = iconContainer
            searchField.leftViewMode = .always

            // Add padding on the right
            let rightPadding = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 20))
            searchField.rightView = rightPadding
            searchField.rightViewMode = .unlessEditing

            searchField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

            view.addSubview(searchField)
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 8).isActive = true
            searchField.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 12).isActive = true
            searchField.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -12).isActive = true
            searchField.heightAnchor.constraint(equalToConstant: 36).isActive = true

            // Table view
            tableView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(tableView)
            tableView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8).isActive = true
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
            tableView.delegate = self
            tableView.dataSource = self
            tableView.separatorStyle = .singleLine
            tableView.keyboardDismissMode = .onDrag

            // Empty label
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            emptyLabel.font = UIFont(name: "Helvetica-Bold", size: 15)
            emptyLabel.textColor = .darkGray
            emptyLabel.textAlignment = .center
            emptyLabel.text = "Type to search"
            view.addSubview(emptyLabel)
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
            emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor).isActive = true
            emptyLabel.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 20).isActive = true
            emptyLabel.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -20).isActive = true

            hasSetupUI = true
        }
    }

    // MARK: - Search Logic

    @objc func textFieldDidChange() {
        searchTimer?.invalidate()

        guard let query = searchField.text, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            songResults = []
            artistResults = []
            albumResults = []
            cachedVisibleSections = visibleSections
            tableView.reloadData()
            emptyLabel.text = "Type to search"
            emptyLabel.isHidden = false
            return
        }

        emptyLabel.isHidden = true

        // Debounce 300ms
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.performSearch(query: query)
        }
    }

    func performSearch(query: String) {
        let lowercaseQuery = query.lowercased()

        // Songs — filter by title
        let allSongs = AppDelegate.music.getSongs().items ?? []
        songResults = allSongs.filter { ($0.title ?? "").lowercased().contains(lowercaseQuery) }
        if songResults.count > 20 { songResults = Array(songResults.prefix(20)) }

        // Artists — filter by name
        let allArtists = AppDelegate.music.getArtists()
        artistResults = allArtists.filter { $0.lowercased().contains(lowercaseQuery) }
        if artistResults.count > 10 { artistResults = Array(artistResults.prefix(10)) }

        // Albums — filter by title
        let allAlbums = AppDelegate.music.getAllAlbums()
        albumResults = allAlbums.filter { ($0.representativeItem?.albumTitle ?? "").lowercased().contains(lowercaseQuery) }
        if albumResults.count > 10 { albumResults = Array(albumResults.prefix(10)) }

        cachedVisibleSections = visibleSections
        tableView.reloadData()

        if songResults.isEmpty && artistResults.isEmpty && albumResults.isEmpty {
            emptyLabel.text = "No Results"
            emptyLabel.isHidden = false
        }
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return cachedVisibleSections.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section < cachedVisibleSections.count else { return nil }
        switch cachedVisibleSections[section] {
        case .songs: return "Songs"
        case .artists: return "Artists"
        case .albums: return "Albums"
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard section < cachedVisibleSections.count else { return 0 }
        switch cachedVisibleSections[section] {
        case .songs: return songResults.count
        case .artists: return artistResults.count
        case .albums: return albumResults.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.section < cachedVisibleSections.count else {
            return UITableViewCell()
        }

        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "SearchCell")
        cell.textLabel?.font = UIFont(name: "Helvetica-Bold", size: 15)
        cell.detailTextLabel?.font = UIFont(name: "Helvetica", size: 12)
        cell.detailTextLabel?.textColor = .gray
        cell.accessoryType = .disclosureIndicator

        switch cachedVisibleSections[indexPath.section] {
        case .songs:
            let song = songResults[indexPath.row]
            cell.textLabel?.text = song.title
            cell.detailTextLabel?.text = song.artist
        case .artists:
            cell.textLabel?.text = artistResults[indexPath.row]
            cell.detailTextLabel?.text = nil
        case .albums:
            let album = albumResults[indexPath.row]
            cell.textLabel?.text = album.representativeItem?.albumTitle
            cell.detailTextLabel?.text = album.representativeItem?.albumArtist ?? album.representativeItem?.artist
        }

        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        searchField.resignFirstResponder()

        guard indexPath.section < cachedVisibleSections.count else { return }

        switch cachedVisibleSections[indexPath.section] {
        case .songs:
            let song = songResults[indexPath.row]
            let vc = PlaybackViewController()
            vc.songs = songResults
            vc.startingIndex = indexPath.row
            self.navigationController?.pushViewController(vc, animated: true)

        case .artists:
            let artist = artistResults[indexPath.row]
            let vc = AlbumsViewController()
            vc.artistName = artist
            self.navigationController?.pushViewController(vc, animated: true)

        case .albums:
            let album = albumResults[indexPath.row]
            if let albumTitle = album.representativeItem?.albumTitle {
                let songs = AppDelegate.music.getSongsInAlbum(forAlbum: albumTitle)
                let vc = SongsViewController()
                vc.menuItems = songs
                vc.albumName = albumTitle
                self.navigationController?.pushViewController(vc, animated: true)
            }
        }
    }
}

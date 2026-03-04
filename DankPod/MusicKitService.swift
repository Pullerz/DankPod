//
//  MusicKitService.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import Foundation
import MediaPlayer
import MusicKit

@available(iOS 15.0, *)
class MusicKitService {
    static let shared = MusicKitService()
    private init() {}
    
    /// Request MusicKit authorization
    func requestAuthorization() async -> MusicAuthorization.Status {
        return await MusicAuthorization.request()
    }
    
    /// Check if MusicKit is authorized
    var isAuthorized: Bool {
        return MusicAuthorization.currentStatus == .authorized
    }
    
    /// Fetch Apple Music curated playlists from the user's library.
    /// Includes personal mixes (Favorites Mix, New Music Mix, etc.),
    /// Replay playlists, and editorial playlists added to the library.
    /// Returns empty array if none found or on error.
    func getPersonalPlaylists() async throws -> [Playlist] {
        if #available(iOS 16.0, *) {
            let request = MusicLibraryRequest<Playlist>()
            let response = try await request.response()
            
            let curatedKinds: Set<Playlist.Kind> = [.personalMix, .replay, .editorial]
            let curated = response.items.filter { playlist in
                if let kind = playlist.kind {
                    return curatedKinds.contains(kind)
                }
                return false
            }
            
            return Array(curated)
        } else {
            return []
        }
    }
    
    /// Fetch tracks for a given playlist by loading it with the .tracks property.
    func getTracks(for playlist: Playlist) async throws -> [Track] {
        let detailedPlaylist = try await playlist.with([.tracks])
        guard let tracks = detailedPlaylist.tracks else { return [] }
        return Array(tracks)
    }
    
    /// Play tracks using the system music player by converting MusicKit Track IDs
    /// to store IDs and setting the queue on MPMusicPlayerController.
    /// Starts playback at the given index.
    func playTracks(_ tracks: [Track], startingAt index: Int = 0) {
        let storeIDs = tracks.compactMap { $0.id.rawValue }
        guard !storeIDs.isEmpty else { return }
        
        // Rearrange so the selected track is first in the queue
        let clampedIndex = min(index, storeIDs.count - 1)
        let rearranged = Array(storeIDs[clampedIndex...]) + Array(storeIDs[..<clampedIndex])
        
        let player = MPMusicPlayerController.systemMusicPlayer
        player.setQueue(with: rearranged)
        player.play()
        
        // Update the playback icon in the nav bar
        AppDelegate.baseVC.setPlaybackIcon(state: .playing)
    }
}

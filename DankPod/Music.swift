//
//  Music.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import Foundation
import MediaPlayer
import UIKit

class Music {
    
    var musicPlayer = MPMusicPlayerController.systemMusicPlayer
    var queueMode: Bool = false
    private var justClearedQueue: Bool = false
    
    init() {
        
    }
    
    func getSongs() -> MPMediaItemCollection {
        let mediaItems = MPMediaQuery.songs().items
        let mediaCollection = MPMediaItemCollection(items: mediaItems ?? [])
        return mediaCollection
    }
    
    func getArtists() -> [String] {
        
        
        var artists: [String] = []
        
        for collection in MPMediaQuery.artists().collections! {
            if let item = collection.representativeItem?.albumArtist {
                if !artists.contains(item) {
                    artists.append(item)
                }
            } else if let item = collection.items[0].albumArtist {
                if !artists.contains(item) {
                    artists.append(item)
                }
            }
        }
        
        
        
        return artists
    }
    
    func getAlbums(forArtist: String) -> [MPMediaItemCollection] {
        //How to search for a particular album
        let albumTitleFilter = MPMediaPropertyPredicate(value: forArtist,
                                 forProperty: MPMediaItemPropertyArtist,
                                 comparisonType: .equalTo)
        
        if let collections = MPMediaQuery(filterPredicates: Set(arrayLiteral: albumTitleFilter)).collections {
            return collections
        } else {
            return []
        }
    }
    
    func getAllAlbums() -> [MPMediaItemCollection] {
        if let albums = MPMediaQuery.albums().collections {
            return albums
        }
        return []
    }
    
    func getSongsInAlbum(forAlbum: String) -> [MPMediaItem] {
        //How to search for a particular album
        let albumTitleFilter = MPMediaPropertyPredicate(value: forAlbum,
                                 forProperty: MPMediaItemPropertyAlbumTitle,
                                 comparisonType: .equalTo)
        
        if let collections = MPMediaQuery(filterPredicates: Set(arrayLiteral: albumTitleFilter)).items {
            return collections
        } else {
            return []
        }
    }
    
    func getPlaylists() -> [MPMediaItemCollection] {
        
        if let playlists = MPMediaQuery.playlists().collections {
            return playlists
        }
        return []
    }
    
    func getGenres() -> [String] {
        var allGenres: [String] = []
        
        let query = MPMediaQuery.genres()
        let genres = query.collections
        for genre in genres! {
            for item in genre.items {
                let genreName = item.value(forProperty: MPMediaItemPropertyGenre) as! String
                if !allGenres.contains(genreName) {
                    allGenres.append(genreName)
                }
            }
        }
        
        return allGenres
    }
    
    func getSongsByGenre(genre: String) -> [MPMediaItemCollection] {
        //How to search for a particular album
        let albumTitleFilter = MPMediaPropertyPredicate(value: genre,
                                 forProperty: MPMediaItemPropertyGenre,
                                 comparisonType: .equalTo)
        
        if let collections = MPMediaQuery(filterPredicates: Set(arrayLiteral: albumTitleFilter)).collections {
            return collections
        } else {
            return []
        }
    }
    
    func setVolume(_ volume: Float) {
        MPVolumeView.setVolume(volume)
    }
    
    func getCurrentQueue() -> [MPMediaItem] {
        if let items = (musicPlayer.value(forKey: "queueAsQuery") as! MPMediaQuery).items {
            return items
        }
        return []
    }

    func playPause() {
        if musicPlayer.playbackState == .playing {
            musicPlayer.pause()
            AppDelegate.baseVC.setPlaybackIcon(state: .paused)
        } else if musicPlayer.playbackState == .paused {
            musicPlayer.play()
            AppDelegate.baseVC.setPlaybackIcon(state: .playing)
        }
    }
    
    func toggleQueueMode() {
        queueMode = !queueMode
        if queueMode {
            print("Current queue length", getCurrentQueue().count)
            clearQueue()
            print("Current queue length", getCurrentQueue().count)
            printQueue()
        } else {
            
        }
    }
    
    func clearQueue() {
        let chosenSong = getSongs().items[0]
            
        musicPlayer.setQueue(with: MPMediaItemCollection(items: [chosenSong]))
        musicPlayer.beginGeneratingPlaybackNotifications()
        musicPlayer.nowPlayingItem = nil
        musicPlayer.play()
        musicPlayer.stop()
        justClearedQueue = true
    }
    
    //If there is currently a song playing then add the songs to a queue variable, when the song ends, append the local queue to the musicPlayer queue using the play+stop trick
    //then clear the local queue
    
    
    func pushToHeadOfQueue(song: MPMediaItem) {
        if musicPlayer.playbackState == .playing {
            //
        } else {
            
        }
    }
    
    func pushToTailOfQueue(song: MPMediaItem) {
        var currentQueue = getCurrentQueue()
        if justClearedQueue {
            currentQueue = [song]
        } else {
            currentQueue.append(song)
        }
        let mediaItemCollection = MPMediaItemCollection(items: currentQueue)
        musicPlayer.setQueue(with: mediaItemCollection)
        let wasPlaying = musicPlayer.playbackState
        if wasPlaying != .playing {
            musicPlayer.play()
            musicPlayer.stop()
        } else {
            
        }
        justClearedQueue = false
    }
    
    func removeFromQueue(song: MPMediaItem) {
        var currentQueue = getCurrentQueue()
        if let index = currentQueue.firstIndex(where: {$0.persistentID == song.persistentID}) {
            currentQueue.remove(at: index)
            let mediaItemCollection = MPMediaItemCollection(items: currentQueue)
            musicPlayer.setQueue(with: mediaItemCollection)
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
        } else {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            generator.impactOccurred()
        }
        
    }
    
    func printQueue() {
        var currentQueue = getCurrentQueue()
        for item in currentQueue {
            print(item.title)
        }
    }
    
    
    
}

extension MPVolumeView {
    static func setVolume(_ volume: Float) {
        let volumeView = MPVolumeView()
        let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.01) {
            slider?.value = volume
        }
    }
}

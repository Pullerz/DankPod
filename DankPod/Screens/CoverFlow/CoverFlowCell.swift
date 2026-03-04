//
//
//  CoverFlowCell.swift
//  DankPod
//
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit
import MediaPlayer

class CoverFlowImagePair {
    let artwork: UIImage
    let reflection: UIImage
    init(artwork: UIImage, reflection: UIImage) {
        self.artwork = artwork
        self.reflection = reflection
    }
}

class CoverFlowCell: UICollectionViewCell {
    
    static let imageCache: NSCache<NSNumber, CoverFlowImagePair> = {
        let cache = NSCache<NSNumber, CoverFlowImagePair>()
        cache.countLimit = 200
        return cache
    }()
    
    private var currentAlbumID: MPMediaEntityPersistentID = 0
    
    let albumArtImageView = UIImageView()
    let reflectionImageView = UIImageView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        
        // Album art — square, fills cell width
        albumArtImageView.contentMode = .scaleAspectFill
        albumArtImageView.clipsToBounds = true
        albumArtImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(albumArtImageView)
        
        // Reflection below artwork — image is pre-rendered: cropped, flipped, and faded
        reflectionImageView.contentMode = .scaleToFill
        reflectionImageView.clipsToBounds = true
        reflectionImageView.translatesAutoresizingMaskIntoConstraints = false
        reflectionImageView.alpha = 0.5
        contentView.addSubview(reflectionImageView)
        
        NSLayoutConstraint.activate([
            // Album art is square: width × width
            albumArtImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            albumArtImageView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            albumArtImageView.rightAnchor.constraint(equalTo: contentView.rightAnchor),
            albumArtImageView.heightAnchor.constraint(equalTo: contentView.widthAnchor),
            
            // Reflection sits directly beneath the art
            reflectionImageView.topAnchor.constraint(equalTo: albumArtImageView.bottomAnchor, constant: 0),
            reflectionImageView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            reflectionImageView.rightAnchor.constraint(equalTo: contentView.rightAnchor),
            reflectionImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }
    
    static func reflectionImage(from source: UIImage) -> UIImage {
        let sourceWidth = source.size.width
        let sourceHeight = source.size.height
        // Reflection shows the bottom 45% of the album art (matches cell proportion)
        let cropFraction: CGFloat = 0.45
        let cropHeight = sourceHeight * cropFraction
        
        // Crop the bottom strip of the source image
        let cropRect = CGRect(x: 0,
                              y: sourceHeight - cropHeight,
                              width: sourceWidth,
                              height: cropHeight)
        guard let croppedCG = source.cgImage?.cropping(to: CGRect(
            x: cropRect.origin.x * source.scale,
            y: cropRect.origin.y * source.scale,
            width: cropRect.width * source.scale,
            height: cropRect.height * source.scale
        )) else {
            return source
        }
        
        let outputSize = CGSize(width: sourceWidth, height: cropHeight)
        let renderer = UIGraphicsImageRenderer(size: outputSize)
        return renderer.image { context in
            let ctx = context.cgContext
            
            // Flip the context vertically so the image draws upside-down
            ctx.translateBy(x: 0, y: outputSize.height)
            ctx.scaleBy(x: 1.0, y: -1.0)
            
            // Draw the cropped portion (now flipped)
            ctx.draw(croppedCG, in: CGRect(origin: .zero, size: outputSize))
            
            // Reset transform for the gradient overlay
            ctx.translateBy(x: 0, y: outputSize.height)
            ctx.scaleBy(x: 1.0, y: -1.0)
            
            // Overlay a white gradient: clear at top (junction), white at bottom (fade out)
            let gradientColors = [
                UIColor.white.withAlphaComponent(0.0).cgColor,
                UIColor.white.withAlphaComponent(0.4).cgColor,
                UIColor.white.withAlphaComponent(0.8).cgColor,
                UIColor.white.cgColor
            ]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let locations: [CGFloat] = [0.0, 0.3, 0.6, 1.0]
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors as CFArray, locations: locations) {
                ctx.setBlendMode(.sourceAtop)
                ctx.drawLinearGradient(gradient,
                                       start: CGPoint(x: outputSize.width / 2, y: 0),
                                       end: CGPoint(x: outputSize.width / 2, y: outputSize.height),
                                       options: [])
            }
        }
    }
    
    static func cacheKey(for album: MPMediaItemCollection) -> NSNumber {
        return NSNumber(value: album.representativeItem?.albumPersistentID ?? 0)
    }
    
    @discardableResult
    static func generateAndCache(for album: MPMediaItemCollection) -> CoverFlowImagePair? {
        let artworkSize = CGSize(width: 200, height: 200)
        guard let artwork = album.representativeItem?.artwork?.image(at: artworkSize) else { return nil }
        let reflection = reflectionImage(from: artwork)
        let pair = CoverFlowImagePair(artwork: artwork, reflection: reflection)
        imageCache.setObject(pair, forKey: cacheKey(for: album))
        return pair
    }
    
    func configure(with album: MPMediaItemCollection) {
        let albumID = album.representativeItem?.albumPersistentID ?? 0
        currentAlbumID = albumID
        
        let key = Self.cacheKey(for: album)
        if let cached = Self.imageCache.object(forKey: key) {
            albumArtImageView.image = cached.artwork
            reflectionImageView.image = cached.reflection
        } else if let pair = Self.generateAndCache(for: album) {
            albumArtImageView.image = pair.artwork
            reflectionImageView.image = pair.reflection
        } else {
            let placeholder = Self.placeholderImages
            albumArtImageView.image = placeholder.artwork
            reflectionImageView.image = placeholder.reflection
        }
    }
    
    private static let placeholderImages: CoverFlowImagePair = {
        let size = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)
        let artwork = renderer.image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let noteFont = UIFont.systemFont(ofSize: size.width * 0.4)
            let noteString = "♪"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: noteFont,
                .foregroundColor: UIColor.gray
            ]
            let textSize = noteString.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            noteString.draw(in: textRect, withAttributes: attributes)
        }
        let reflection = reflectionImage(from: artwork)
        return CoverFlowImagePair(artwork: artwork, reflection: reflection)
    }()
    
    override func prepareForReuse() {
        super.prepareForReuse()
        currentAlbumID = 0
    }
}

//
//  CoverFlowCell.swift
//  DankPod
//
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit
import MediaPlayer

class CoverFlowCell: UICollectionViewCell {
    
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
        
        // Reflection below artwork — image is pre-rendered with gradient baked in
        reflectionImageView.contentMode = .scaleAspectFill
        reflectionImageView.clipsToBounds = true
        reflectionImageView.translatesAutoresizingMaskIntoConstraints = false
        reflectionImageView.transform = CGAffineTransform(scaleX: 1.02, y: -0.92)
        contentView.addSubview(reflectionImageView)
        
        NSLayoutConstraint.activate([
            // Album art is square: width × width
            albumArtImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            albumArtImageView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            albumArtImageView.rightAnchor.constraint(equalTo: contentView.rightAnchor),
            albumArtImageView.heightAnchor.constraint(equalTo: contentView.widthAnchor),
            
            // Reflection sits directly beneath the art
            reflectionImageView.topAnchor.constraint(equalTo: albumArtImageView.bottomAnchor, constant: 0),
            reflectionImageView.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: -4),
            reflectionImageView.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: 4),
            reflectionImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }
    
    /// Creates a reflection image with a vertical gradient fade baked in.
    /// The gradient goes from semi-visible at the top to fully transparent,
    /// matching the iPod Classic reflection diffusion effect.
    private func reflectionImage(from source: UIImage) -> UIImage {
        let size = source.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            // Draw the source image
            source.draw(in: rect)
            
            // Overlay a gradient that goes from clear (top) to the background color (bottom).
            // Because the reflection view is flipped (negative Y scale), the "top" of this
            // image becomes the bottom of the visual reflection, and "bottom" becomes the
            // junction with the album art. So we fade from clear at bottom to opaque at top.
            let gradientColors = [
                UIColor.white.withAlphaComponent(0.55).cgColor,
                UIColor.white.withAlphaComponent(0.7).cgColor,
                UIColor.white.withAlphaComponent(1.0).cgColor
            ]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let locations: [CGFloat] = [0.0, 0.35, 0.65]
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors as CFArray, locations: locations) {
                context.cgContext.setBlendMode(.sourceAtop)
                context.cgContext.drawLinearGradient(gradient,
                                                     start: CGPoint(x: size.width / 2, y: 0),
                                                     end: CGPoint(x: size.width / 2, y: size.height),
                                                     options: [])
            }
        }
    }
    
    func configure(with album: MPMediaItemCollection) {
        let artworkSize = CGSize(width: 200, height: 200)
        if let artwork = album.representativeItem?.artwork?.image(at: artworkSize) {
            albumArtImageView.image = artwork
            reflectionImageView.image = reflectionImage(from: artwork)
        } else {
            // Placeholder: dark grey with music note
            let placeholderImage = createPlaceholderImage(size: artworkSize)
            albumArtImageView.image = placeholderImage
            reflectionImageView.image = reflectionImage(from: placeholderImage)
        }
    }
    
    private func createPlaceholderImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // Draw a music note symbol
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
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        albumArtImageView.image = nil
        reflectionImageView.image = nil
    }
}

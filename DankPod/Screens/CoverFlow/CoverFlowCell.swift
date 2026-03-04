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
    private let reflectionGradient = CAGradientLayer()
    
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
        
        // Album art - top 75% of the cell
        albumArtImageView.contentMode = .scaleAspectFill
        albumArtImageView.clipsToBounds = true
        albumArtImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(albumArtImageView)
        
        // Reflection - bottom 25% of the cell, below album art
        reflectionImageView.contentMode = .scaleAspectFill
        reflectionImageView.clipsToBounds = true
        reflectionImageView.translatesAutoresizingMaskIntoConstraints = false
        reflectionImageView.transform = CGAffineTransform(scaleX: 1, y: -1)
        contentView.addSubview(reflectionImageView)
        
        NSLayoutConstraint.activate([
            // Album art is square: width × width
            albumArtImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            albumArtImageView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            albumArtImageView.rightAnchor.constraint(equalTo: contentView.rightAnchor),
            albumArtImageView.heightAnchor.constraint(equalTo: contentView.widthAnchor),
            
            // Reflection fills the remaining space below the square art
            reflectionImageView.topAnchor.constraint(equalTo: albumArtImageView.bottomAnchor),
            reflectionImageView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            reflectionImageView.rightAnchor.constraint(equalTo: contentView.rightAnchor),
            reflectionImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Update reflection gradient mask
        reflectionGradient.frame = reflectionImageView.bounds
        reflectionGradient.colors = [
            UIColor.white.withAlphaComponent(0.3).cgColor,
            UIColor.clear.cgColor
        ]
        reflectionGradient.startPoint = CGPoint(x: 0.5, y: 0)
        reflectionGradient.endPoint = CGPoint(x: 0.5, y: 1)
        reflectionImageView.layer.mask = reflectionGradient
    }
    
    func configure(with album: MPMediaItemCollection) {
        let artworkSize = CGSize(width: 200, height: 200)
        if let artwork = album.representativeItem?.artwork?.image(at: artworkSize) {
            albumArtImageView.image = artwork
            reflectionImageView.image = artwork
        } else {
            // Placeholder: dark grey with music note
            let placeholderImage = createPlaceholderImage(size: artworkSize)
            albumArtImageView.image = placeholderImage
            reflectionImageView.image = placeholderImage
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

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
    let reflectionSpreadImageView = UIImageView()
    private let reflectionGradient = CAGradientLayer()
    private let reflectionSpreadGradient = CAGradientLayer()
    
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
        
        // Diffused reflection spread layer (wider + softer), sits behind main reflection
        reflectionSpreadImageView.contentMode = .scaleAspectFill
        reflectionSpreadImageView.clipsToBounds = true
        reflectionSpreadImageView.translatesAutoresizingMaskIntoConstraints = false
        reflectionSpreadImageView.transform = CGAffineTransform(scaleX: 1, y: -1)
        reflectionSpreadImageView.alpha = 0.2
        contentView.addSubview(reflectionSpreadImageView)
        
        // Reflection — crisp layer near contact point
        reflectionImageView.contentMode = .scaleAspectFill
        reflectionImageView.clipsToBounds = true
        reflectionImageView.translatesAutoresizingMaskIntoConstraints = false
        reflectionImageView.transform = CGAffineTransform(scaleX: 1, y: -1)
        reflectionImageView.alpha = 0.55
        contentView.addSubview(reflectionImageView)
        
        NSLayoutConstraint.activate([
            // Album art is square: width × width
            albumArtImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            albumArtImageView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            albumArtImageView.rightAnchor.constraint(equalTo: contentView.rightAnchor),
            albumArtImageView.heightAnchor.constraint(equalTo: contentView.widthAnchor),
            
            // Wider diffused reflection starts just below the art
            reflectionSpreadImageView.topAnchor.constraint(equalTo: albumArtImageView.bottomAnchor, constant: 1),
            reflectionSpreadImageView.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: -8),
            reflectionSpreadImageView.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: 8),
            reflectionSpreadImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            // Main reflection sits on top with a tiny gap from the art
            reflectionImageView.topAnchor.constraint(equalTo: albumArtImageView.bottomAnchor, constant: 2),
            reflectionImageView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            reflectionImageView.rightAnchor.constraint(equalTo: contentView.rightAnchor),
            reflectionImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Main reflection mask: visible near the seam, fades quickly
        reflectionGradient.frame = reflectionImageView.bounds
        reflectionGradient.colors = [
            UIColor.white.cgColor,
            UIColor.white.withAlphaComponent(0.35).cgColor,
            UIColor.clear.cgColor
        ]
        reflectionGradient.locations = [0.0, 0.2, 0.65]
        reflectionGradient.startPoint = CGPoint(x: 0.5, y: 0)
        reflectionGradient.endPoint = CGPoint(x: 0.5, y: 1)
        reflectionImageView.layer.mask = reflectionGradient
        
        // Spread mask: softer and broader falloff for surface diffusion
        reflectionSpreadGradient.frame = reflectionSpreadImageView.bounds
        reflectionSpreadGradient.colors = [
            UIColor.white.withAlphaComponent(0.65).cgColor,
            UIColor.white.withAlphaComponent(0.2).cgColor,
            UIColor.clear.cgColor
        ]
        reflectionSpreadGradient.locations = [0.0, 0.35, 1.0]
        reflectionSpreadGradient.startPoint = CGPoint(x: 0.5, y: 0)
        reflectionSpreadGradient.endPoint = CGPoint(x: 0.5, y: 1)
        reflectionSpreadImageView.layer.mask = reflectionSpreadGradient
    }
    
    func configure(with album: MPMediaItemCollection) {
        let artworkSize = CGSize(width: 200, height: 200)
        if let artwork = album.representativeItem?.artwork?.image(at: artworkSize) {
            albumArtImageView.image = artwork
            reflectionImageView.image = artwork
            reflectionSpreadImageView.image = artwork
        } else {
            // Placeholder: dark grey with music note
            let placeholderImage = createPlaceholderImage(size: artworkSize)
            albumArtImageView.image = placeholderImage
            reflectionImageView.image = placeholderImage
            reflectionSpreadImageView.image = placeholderImage
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
        reflectionSpreadImageView.image = nil
    }
}

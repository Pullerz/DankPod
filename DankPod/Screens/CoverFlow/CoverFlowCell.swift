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
        
        // Album art — square, fills cell width
        albumArtImageView.contentMode = .scaleAspectFill
        albumArtImageView.clipsToBounds = true
        albumArtImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(albumArtImageView)
        
        // Reflection below artwork
        reflectionImageView.contentMode = .scaleAspectFill
        reflectionImageView.clipsToBounds = true
        reflectionImageView.translatesAutoresizingMaskIntoConstraints = false
        reflectionImageView.transform = CGAffineTransform(scaleX: 1.06, y: -0.72)
        reflectionImageView.alpha = 0.38
        contentView.addSubview(reflectionImageView)
        
        NSLayoutConstraint.activate([
            // Album art is square: width × width
            albumArtImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            albumArtImageView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            albumArtImageView.rightAnchor.constraint(equalTo: contentView.rightAnchor),
            albumArtImageView.heightAnchor.constraint(equalTo: contentView.widthAnchor),
            
            // Reflection sits with a tiny gap from the art
            reflectionImageView.topAnchor.constraint(equalTo: albumArtImageView.bottomAnchor, constant: 1),
            reflectionImageView.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: -4),
            reflectionImageView.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: 4),
            reflectionImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Reflection mask: visible near seam then diffuses downward
        reflectionGradient.frame = reflectionImageView.bounds
        reflectionGradient.colors = [
            UIColor.white.cgColor,
            UIColor.white.withAlphaComponent(0.35).cgColor,
            UIColor.white.withAlphaComponent(0.08).cgColor,
            UIColor.clear.cgColor
        ]
        reflectionGradient.locations = [0.0, 0.12, 0.45, 1.0]
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

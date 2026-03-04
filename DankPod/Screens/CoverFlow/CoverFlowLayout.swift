//
//  CoverFlowLayout.swift
//  DankPod
//
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class CoverFlowLayout: UICollectionViewFlowLayout {
    
    // Angle in degrees that side covers are rotated around the Y axis
    let tiltAngle: CGFloat = 58
    // Horizontal distance from the center cover's center to the first side cover's center
    let sideOffset: CGFloat = 72
    // Horizontal spacing between successive side covers (tight stacking/overlapping)
    let sideSpacing: CGFloat = 12
    // Z-depth that side covers are pushed behind the center
    let sideDepth: CGFloat = 170
    // Distance in points over which an item transitions from center to side state
    var transitionDistance: CGFloat = 0
    private var cachedBoundsSize: CGSize = .zero
    
    override func prepare() {
        super.prepare()
        scrollDirection = .horizontal
        guard let collectionView = collectionView else { return }
        // Only recompute metrics when bounds size changes (not on every scroll tick)
        guard collectionView.bounds.size != cachedBoundsSize else { return }
        cachedBoundsSize = collectionView.bounds.size
        // Art is square; cell is taller to fit reflection below
        let artSize = collectionView.bounds.height * 0.5
        itemSize = CGSize(width: artSize, height: artSize * 1.45)
        // Positive spacing — items are spaced apart; transforms handle visual positioning
        minimumLineSpacing = 10
        let horizontalInset = (collectionView.bounds.width - itemSize.width) / 2.0
        sectionInset = UIEdgeInsets(top: 0, left: horizontalInset, bottom: 0, right: horizontalInset)
        // Distance over which the center-to-side transition occurs
        transitionDistance = itemSize.width + minimumLineSpacing
    }
    
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return true
    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let collectionView = collectionView else { return nil }
        
        // Expand the rect to capture items that may be transformed into the visible area
        // Use half the viewport width — enough for the 3D perspective but avoids creating
        // cells far beyond what's visible
        let expandedRect = rect.insetBy(dx: -collectionView.bounds.width * 0.5, dy: 0)
        guard let superAttributes = super.layoutAttributesForElements(in: expandedRect) else { return nil }
        
        let centerX = collectionView.contentOffset.x + collectionView.bounds.width / 2.0
        let layoutSpacing = itemSize.width + minimumLineSpacing
        let attributes = superAttributes.map { $0.copy() as! UICollectionViewLayoutAttributes }
        
        for attribute in attributes {
            let distance = attribute.center.x - centerX
            // How many item-widths away from center
            let normalizedDistance = distance / layoutSpacing
            let absNormalized = abs(normalizedDistance)
            let sign: CGFloat = normalizedDistance >= 0 ? 1.0 : -1.0

            // Only center transitions; once item leaves center neighborhood it has constant side tilt.
            let centerTransitionWidth: CGFloat = 0.75
            let linearFactor = min(absNormalized / centerTransitionWidth, 1.0)
            let sideFactor = linearFactor * linearFactor * (3.0 - 2.0 * linearFactor)
            let angle = -sign * sideFactor * tiltAngle * .pi / 180.0

            var desiredX: CGFloat
            if absNormalized < 0.01 {
                desiredX = centerX
            } else {
                let sideIndex = max(absNormalized - 1.0, 0.0)
                let sideX = centerX + sign * (sideOffset + sideIndex * sideSpacing)
                if absNormalized < 1.0 {
                    let naturalX = centerX + distance
                    desiredX = naturalX + (sideX - naturalX) * sideFactor
                } else {
                    desiredX = sideX
                }
            }

            let translateX = desiredX - attribute.center.x
            let depth = -sideFactor * sideDepth
            
            // Build transform: translate first (in parent coords), then rotate (around anchor)
            var transform = CATransform3DIdentity
            transform.m34 = -1.0 / 900.0
            // Translate to the desired visual position and push back in Z
            transform = CATransform3DTranslate(transform, translateX, 0, depth)
            // Rotate around Y axis — happens around the item's center after translation
            transform = CATransform3DRotate(transform, angle, 0, 1, 0)
            
            attribute.transform3D = transform
            
            // Z-index: center item on top, side items layered by distance
            attribute.zIndex = Int(10000 - absNormalized * 100)
        }
        
        return attributes
    }
    
    // Returns the exact content offset.x needed to center the item at the given index
    func contentOffsetForItem(at index: Int) -> CGFloat {
        return contentOffsetForFractionalPosition(Double(index))
    }
    
    // Returns interpolated content offset for a fractional album position (e.g. 5.3)
    func contentOffsetForFractionalPosition(_ position: Double) -> CGFloat {
        let layoutSpacing = itemSize.width + minimumLineSpacing
        let itemCenterX = sectionInset.left + itemSize.width / 2.0 + CGFloat(position) * layoutSpacing
        let viewportWidth = collectionView?.bounds.width ?? 0
        return itemCenterX - viewportWidth / 2.0
    }
    
    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint, withScrollingVelocity velocity: CGPoint) -> CGPoint {
        guard let collectionView = collectionView else {
            return super.targetContentOffset(forProposedContentOffset: proposedContentOffset, withScrollingVelocity: velocity)
        }
        
        let centerX = proposedContentOffset.x + collectionView.bounds.width / 2.0
        let targetRect = CGRect(x: proposedContentOffset.x - collectionView.bounds.width,
                                y: 0,
                                width: collectionView.bounds.width * 3,
                                height: collectionView.bounds.height)
        
        guard let attributes = super.layoutAttributesForElements(in: targetRect) else {
            return super.targetContentOffset(forProposedContentOffset: proposedContentOffset, withScrollingVelocity: velocity)
        }
        
        var closestAttribute: UICollectionViewLayoutAttributes?
        var closestDistance = CGFloat.greatestFiniteMagnitude
        
        for attribute in attributes {
            let distance = attribute.center.x - centerX
            if abs(distance) < abs(closestDistance) {
                closestDistance = distance
                closestAttribute = attribute
            }
        }
        
        guard let closest = closestAttribute else {
            return super.targetContentOffset(forProposedContentOffset: proposedContentOffset, withScrollingVelocity: velocity)
        }
        
        let offsetX = closest.center.x - collectionView.bounds.width / 2.0
        return CGPoint(x: offsetX, y: proposedContentOffset.y)
    }
}

//
//  CoverFlowLayout.swift
//  DankPod
//
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class CoverFlowLayout: UICollectionViewFlowLayout {
    
    // Angle in degrees that side covers are rotated around the Y axis
    let tiltAngle: CGFloat = 70
    // Horizontal distance from the center cover's center to the first side cover's center
    let sideOffset: CGFloat = 110
    // Horizontal spacing between successive side covers (tight stacking)
    let sideSpacing: CGFloat = 42
    // Z-depth that side covers are pushed behind the center
    let sideDepth: CGFloat = 200
    // Distance in points over which an item transitions from center to side state
    var transitionDistance: CGFloat = 0
    
    override func prepare() {
        super.prepare()
        scrollDirection = .horizontal
        guard let collectionView = collectionView else { return }
        let itemHeight = collectionView.bounds.height * 0.6
        itemSize = CGSize(width: itemHeight, height: itemHeight)
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
        let expandedRect = rect.insetBy(dx: -collectionView.bounds.width, dy: 0)
        guard let superAttributes = super.layoutAttributesForElements(in: expandedRect) else { return nil }
        
        let centerX = collectionView.contentOffset.x + collectionView.bounds.width / 2.0
        let layoutSpacing = itemSize.width + minimumLineSpacing
        let attributes = superAttributes.map { $0.copy() as! UICollectionViewLayoutAttributes }
        
        for attribute in attributes {
            let distance = attribute.center.x - centerX
            // How many "item widths" away from center (can be fractional for smooth animation)
            let normalizedDistance = distance / layoutSpacing
            let absNormalized = abs(normalizedDistance)
            
            // Transition factor: 0 = fully centered, 1 = fully side-state
            // Smooth transition over the range [0, 1] item widths
            let t = min(absNormalized, 1.0)
            let sign: CGFloat = normalizedDistance >= 0 ? 1.0 : -1.0
            
            // Rotation: 0 at center, full tiltAngle at sides
            let angle = sign * t * tiltAngle * .pi / 180.0
            
            // Calculate where this item SHOULD be visually vs where the layout placed it.
            // The layout places item N at: centerX + N * layoutSpacing
            // We want item N to be at:
            //   - Center item (N=0): centerX (no change)
            //   - Side items: centerX + sign * (sideOffset + (absN - 1) * sideSpacing)
            // The translation is the difference between desired and actual position.
            var desiredX: CGFloat
            if absNormalized < 0.01 {
                desiredX = centerX
            } else if absNormalized < 1.0 {
                // Transitioning: interpolate between natural center and first side position
                let sideX = centerX + sign * sideOffset
                let naturalX = centerX + distance
                // Smoothly move from natural position toward side position
                desiredX = naturalX + (sideX - naturalX) * t
            } else {
                // Fully in side state: stack tightly
                let sideIndex = absNormalized - 1.0
                desiredX = centerX + sign * (sideOffset + sideIndex * sideSpacing)
            }
            
            let translateX = desiredX - attribute.center.x
            let depth = -t * sideDepth
            
            // Build transform: translate first (in parent coords), then rotate (around anchor)
            var transform = CATransform3DIdentity
            transform.m34 = -1.0 / 800.0
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

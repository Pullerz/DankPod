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
    let sideOffset: CGFloat = 85
    // Horizontal spacing between successive side covers (tight stacking/overlapping)
    let sideSpacing: CGFloat = 14
    // Z-depth that side covers are pushed behind the center
    let sideDepth: CGFloat = 200
    // Distance in points over which an item transitions from center to side state
    var transitionDistance: CGFloat = 0
    
    override func prepare() {
        super.prepare()
        scrollDirection = .horizontal
        guard let collectionView = collectionView else { return }
        // Art is square; cell is taller to fit reflection below
        let artSize = collectionView.bounds.height * 0.5
        itemSize = CGSize(width: artSize, height: artSize * 1.3)
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
            // Ramp up fast so side items snap to full tilt quickly (×3 then clamp)
            let t = min(absNormalized * 3.0, 1.0)
            let sign: CGFloat = normalizedDistance >= 0 ? 1.0 : -1.0
            
            // Rotation: 0 at center, full tiltAngle at sides — constant angle once tilted
            let angle = -sign * t * tiltAngle * .pi / 180.0
            
            // Calculate where this item SHOULD be visually vs where the layout placed it.
            // Center item stays put; side items stack tightly with overlap.
            var desiredX: CGFloat
            if absNormalized < 0.01 {
                desiredX = centerX
            } else {
                // All non-center items: position based on their distance from center
                // First side item at sideOffset, subsequent items stacked at sideSpacing apart
                let sideIndex = max(absNormalized - 1.0, 0.0)
                let fullSideX = centerX + sign * (sideOffset + sideIndex * sideSpacing)
                
                if absNormalized < 1.0 {
                    // Transitioning: interpolate toward side position
                    let naturalX = centerX + distance
                    desiredX = naturalX + (fullSideX - naturalX) * t
                } else {
                    desiredX = fullSideX
                }
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
    
    // Returns the exact content offset.x needed to center the item at the given index
    func contentOffsetForItem(at index: Int) -> CGFloat {
        let layoutSpacing = itemSize.width + minimumLineSpacing
        // Item N's center.x in content coordinates = sectionInset.left + itemSize.width/2 + N * layoutSpacing
        let itemCenterX = sectionInset.left + itemSize.width / 2.0 + CGFloat(index) * layoutSpacing
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

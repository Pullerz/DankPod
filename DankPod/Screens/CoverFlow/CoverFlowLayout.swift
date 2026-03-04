//
//  CoverFlowLayout.swift
//  DankPod
//
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class CoverFlowLayout: UICollectionViewFlowLayout {
    
    // Angle in degrees that side covers are rotated around the Y axis
    let tiltAngle: CGFloat = 62
    // Horizontal distance from the center cover's center to the first side cover's center
    let sideOffset: CGFloat = 66
    // Horizontal spacing between successive side covers (tight stacking/overlapping)
    let sideSpacing: CGFloat = 10
    // Z-depth that side covers are pushed behind the center
    let sideDepth: CGFloat = 150
    // Distance in points over which an item transitions from center to side state
    var transitionDistance: CGFloat = 0
    
    override func prepare() {
        super.prepare()
        scrollDirection = .horizontal
        guard let collectionView = collectionView else { return }
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
        let expandedRect = rect.insetBy(dx: -collectionView.bounds.width, dy: 0)
        guard let superAttributes = super.layoutAttributesForElements(in: expandedRect) else { return nil }
        
        let centerX = collectionView.contentOffset.x + collectionView.bounds.width / 2.0
        let layoutSpacing = itemSize.width + minimumLineSpacing
        let attributes = superAttributes.map { $0.copy() as! UICollectionViewLayoutAttributes }
        
        for attribute in attributes {
            let distance = attribute.center.x - centerX
            // How many layout slots away from center (fractional)
            let normalizedDistance = distance / layoutSpacing
            let sign: CGFloat = normalizedDistance >= 0 ? 1.0 : -1.0
            let absNormalized = abs(normalizedDistance)
            
            // Snap side items to discrete slot indices to avoid progressive tilt in settled states.
            let nearestSlot = Int(round(absNormalized))
            let isCenter = nearestSlot == 0
            
            let slotProgress = min(abs(absNormalized - CGFloat(nearestSlot)) * 2.0, 1.0)
            let transition = 1.0 - slotProgress
            
            let sideSlot = max(nearestSlot - 1, 0)
            let slotX = centerX + sign * (sideOffset + CGFloat(sideSlot) * sideSpacing)
            let naturalX = centerX + distance
            let desiredX = isCenter ? centerX : (naturalX + (slotX - naturalX) * transition)
            
            let sideFactor: CGFloat = isCenter ? 0.0 : transition
            let angle = -sign * sideFactor * tiltAngle * .pi / 180.0
            let translateX = desiredX - attribute.center.x
            let depth = -sideFactor * sideDepth
            
            // Build transform: translate first (in parent coords), then rotate (around anchor)
            var transform = CATransform3DIdentity
            transform.m34 = -1.0 / 1100.0
            // Translate to the desired visual position and push back in Z
            transform = CATransform3DTranslate(transform, translateX, 0, depth)
            // Rotate around Y axis — happens around the item's center after translation
            transform = CATransform3DRotate(transform, angle, 0, 1, 0)
            
            attribute.transform3D = transform
            
            // Z-index: center item on top, side items layered by distance
            attribute.zIndex = isCenter ? 10000 : Int(9000 - CGFloat(sideSlot) * 10)
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

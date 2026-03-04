//
//  CoverFlowLayout.swift
//  DankPod
//
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class CoverFlowLayout: UICollectionViewFlowLayout {
    
    let activeDistance: CGFloat = 200
    let tiltAngle: CGFloat = 70
    let scaleFactor: CGFloat = 0.75
    let centerGap: CGFloat = 30
    
    override func prepare() {
        super.prepare()
        scrollDirection = .horizontal
        guard let collectionView = collectionView else { return }
        let itemHeight = collectionView.bounds.height * 0.6
        itemSize = CGSize(width: itemHeight, height: itemHeight)
        minimumLineSpacing = -itemHeight * 0.15  // Negative for overlap of side items
        let horizontalInset = (collectionView.bounds.width - itemSize.width) / 2.0
        sectionInset = UIEdgeInsets(top: 0, left: horizontalInset, bottom: 0, right: horizontalInset)
    }
    
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return true
    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let superAttributes = super.layoutAttributesForElements(in: rect),
              let collectionView = collectionView else { return nil }
        
        let centerX = collectionView.contentOffset.x + collectionView.bounds.width / 2.0
        let attributes = superAttributes.map { $0.copy() as! UICollectionViewLayoutAttributes }
        
        for attribute in attributes {
            let distance = attribute.center.x - centerX
            let normalizedDistance = distance / activeDistance
            let clampedDistance = max(-1, min(1, normalizedDistance))
            
            var transform = CATransform3DIdentity
            transform.m34 = -1.0 / 500.0  // Perspective
            
            if abs(clampedDistance) < 0.05 {
                // Center item: no rotation, full scale, highest z-index
                attribute.zIndex = 1000
            } else {
                // Side items: rotate around Y axis
                let angle = clampedDistance * tiltAngle * .pi / 180.0
                transform = CATransform3DRotate(transform, angle, 0, 1, 0)
                
                // Scale down side items
                let scale = 1.0 - abs(clampedDistance) * (1.0 - scaleFactor)
                transform = CATransform3DScale(transform, scale, scale, 1.0)
                
                // Translate side items toward center for overlap effect
                let translateX = -clampedDistance * centerGap
                transform = CATransform3DTranslate(transform, translateX, 0, -abs(clampedDistance) * 400)
                
                attribute.zIndex = Int(1000 - abs(distance))
            }
            
            attribute.transform3D = transform
        }
        
        return attributes
    }
    
    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint, withScrollingVelocity velocity: CGPoint) -> CGPoint {
        guard let collectionView = collectionView else {
            return super.targetContentOffset(forProposedContentOffset: proposedContentOffset, withScrollingVelocity: velocity)
        }
        
        let centerX = proposedContentOffset.x + collectionView.bounds.width / 2.0
        let targetRect = CGRect(x: proposedContentOffset.x, y: 0, width: collectionView.bounds.width, height: collectionView.bounds.height)
        
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

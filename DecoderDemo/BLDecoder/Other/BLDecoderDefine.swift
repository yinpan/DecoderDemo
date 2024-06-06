//
//  BLDecoderDefine.swift
//  DecoderDemo
//
//  Created by yinpan on 2024/6/5.
//

import Foundation

/// 根据'expect'来缩放sourceWidth和sourceHeight
func calculateScaledSize(_ sourceWidth: CGFloat, _ sourceHeight: CGFloat, _ expect: CGSize) -> CGSize {
    var previewWidth = sourceWidth
    var previewHeight = sourceHeight
    let expectSize = expect
    if previewWidth > CGFloat(expectSize.width) {
        let scale: CGFloat =  CGFloat(expectSize.width) / previewWidth
        previewWidth *= scale
        previewHeight *= scale
    }
    if previewHeight > CGFloat(expectSize.height) {
        let scale: CGFloat =  CGFloat(expectSize.height) / previewHeight
        previewWidth *= scale
        previewHeight *= scale
    }

    let size = CGSize(width: Int(ceil(previewWidth)), height: Int(ceil(previewHeight)))
    //MSLog.debug("--calculateScaledSize--:\(previewWidth)--:\(previewHeight)--nextUp:\(size.width)---\(size.height)")
    return size
}

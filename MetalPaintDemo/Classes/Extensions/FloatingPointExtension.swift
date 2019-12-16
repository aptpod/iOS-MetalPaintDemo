//
//  FloatingPointExtension.swift
//  MetalPaintDemo
//
//  Created by Ueno Masamitsu on 2019/12/09.
//  Copyright © 2019 aptpod,Inc. All rights reserved.
//

import Foundation

extension FloatingPoint {
    
    var degreesToRadians: Self { return self * .pi / 180 }
    var radiansToDegrees: Self { return self * 180 / .pi }
    
}

//
//  PaintShader.metal
//  iOS-MetalPaintDemo
//
//  Created by Ueno Masamitsu on 2019/12/05.
//  Copyright © 2019 aptpod,Inc. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

/*
 * |--|--|--|--|
 * | 0| 4| 8|12|
 * | 1| 5| 9|13|
 * | 2| 6|10|14|
 * | 3| 7|11|15|
 * |--|--|--|--|
 */
kernel void computeTexture2d(texture2d<half, access::write> output [[texture(0)]],
                             device float4 *color_buffer [[buffer(1)]],
                             uint2 gid [[thread_position_in_grid]]) {
    int h = output.get_height();
    int index = (gid.x * h) + gid.y;
    half r = color_buffer[index].x;
    half g = color_buffer[index].y;
    half b = color_buffer[index].z;
    half a = color_buffer[index].w;
    output.write(half4(r, g, b, a), gid);
}


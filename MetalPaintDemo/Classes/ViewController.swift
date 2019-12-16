//
//  ViewController.swift
//  MetalPaintDemo
//
//  Created by Ueno Masamitsu on 2019/12/05.
//  Copyright © 2019 aptpod,Inc. All rights reserved.
//

import UIKit
import MetalKit

// Colors
let kRed = UIColor.red
let kGreen = UIColor.green
let kBlue = UIColor.blue
let kWhite = UIColor.white
let kBlack = UIColor.black

// Metal
let kMetalTextureHeightDotSize: Int = 512
let kMetalThreadGroupCount: Int = 16
let kMetalTextureClearColor: simd_float4 = [255/255.0, 255/255.0, 255/255.0, 1.0]

// PointSize
let kMaxPointSize = 64
let kDefaultPointSize = 1
let kMinPointSize = 1

class ViewController: UIViewController, MTKViewDelegate {
    
    // MARK:- viewDidLoad
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        self.log("viewDidLoad")
        
        // Setup Funcions
        self.setupViewEvents()
        self.setupMetalView()
    }

    //MARK:- View Events
    @IBOutlet weak var redBtn: UIButton!
    @IBOutlet weak var greenBtn: UIButton!
    @IBOutlet weak var blueBtn: UIButton!
    @IBOutlet weak var clearBtn: UIButton!
    
    private var isRed: Bool = false {
        didSet {
            self.redBtn.setTitleColor(self.isRed ? kWhite : kRed, for: .normal)
            self.redBtn.backgroundColor = self.isRed ? kRed : kBlack
            self.redBtn.layer.borderColor = self.isRed ? kWhite.cgColor : kRed.cgColor
        }
    }
    private var isGreen: Bool = false {
        didSet {
            self.greenBtn.setTitleColor(self.isGreen ? kWhite : kGreen, for: .normal)
            self.greenBtn.backgroundColor = self.isGreen ? kGreen : kBlack
            self.greenBtn.layer.borderColor = self.isGreen ? kWhite.cgColor : kGreen.cgColor
        }
    }
    private var isBlue: Bool = false {
        didSet {
            self.blueBtn.setTitleColor(self.isBlue ? kWhite : kBlue, for: .normal)
            self.blueBtn.backgroundColor = self.isBlue ? kBlue : kBlack
            self.blueBtn.layer.borderColor = self.isBlue ? kWhite.cgColor : kBlue.cgColor
        }
    }
    
    // PointSize
    @IBOutlet weak var pointSizeLabel: UILabel!
    var pointSize: Int = -1 {
        didSet {
            self.pointSizeLabel.text = "\(self.pointSize)pt"
        }
    }
    
    func setupViewEvents() {
        self.redBtn.addTarget(self, action: #selector(redBtnPushed(sender:)), for: .touchUpInside)
        self.greenBtn.addTarget(self, action: #selector(greenBtnPushed(sender:)), for: .touchUpInside)
        self.blueBtn.addTarget(self, action: #selector(blueBtnPushed(sender:)), for: .touchUpInside)
        self.clearBtn.addTarget(self, action: #selector(clearBtnPushed(sender:)), for: .touchUpInside)
        self.pointSize = kDefaultPointSize
    }
    
    @IBAction func redBtnPushed(sender: Any) {
        self.isRed = !self.isRed
    }
    
    @IBAction func greenBtnPushed(sender: Any) {
        self.isGreen = !self.isGreen
    }
    
    @IBAction func blueBtnPushed(sender: Any) {
        self.isBlue = !self.isBlue
    }
    
    @IBAction func clearBtnPushed(sender: Any) {
        self.setupMetalBuffer()
    }
    
    //MARK:- Change PointSize Events
    @IBAction func upBtnPushed(sender: Any) {
        var newPointSize = self.pointSize * 2
        if newPointSize > kMaxPointSize {
            newPointSize = kMaxPointSize
        }
        self.pointSize = newPointSize
    }
    
    @IBAction func downBtnPushed(sender: Any) {
        var newPointSize = self.pointSize / 2
        if newPointSize < kMinPointSize {
            newPointSize = kMinPointSize
        }
        self.pointSize = newPointSize
    }
    
    //MARK:- TouchEvents
    // 前回のタッチ位置
    var lastPoint: CGPoint? = nil
    
    // タッチイベントが開始された
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = event?.touches(for: self.metalView)?.first else { return }
        let point = touch.location(in: self.metalView)
        self.log("touchBegan: \(point) - metalView")
        self.lastPoint = nil
        self.drawCanvas(point: point)
    }
    
    // タッチ位置が移動した
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = event?.touches(for: self.metalView)?.first else { return }
        let point = touch.location(in: self.metalView)
        self.log("touchesMoved: \(point) - metalView")
        self.drawCanvas(point: point)
    }
    
    // タッチが終了した
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = event?.touches(for: self.metalView)?.first else { return }
        let point = touch.location(in: self.metalView)
        self.log("touchesEnded: \(point) - metalView")
        self.drawCanvas(point: point)
    }
    
    // タッチがキャンセルされた
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.log("touchesCancelled")
    }
    
    // MARK:- viewDidAppear
    override func viewDidAppear(_ animated: Bool) {
        self.log("viewDidAppear")
        self.updateMetalViewDrawableSize()
    }
    
    // MARK:- viewWillTransition
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        self.log("viewWillTransition")
        self.metalView.delegate = nil // ここでMetalViewにDelegateを呼ばれない様にしてあげると管理が楽
        coordinator.animate(alongsideTransition: nil) { (_) in
            self.metalView.delegate = self
            self.updateMetalViewDrawableSize()
        }
    }
    
    // MARK:- Metal View
    @IBOutlet weak var metalView: MTKView!
    
    var mDevice = MTLCreateSystemDefaultDevice()
    var mCommandQueue: MTLCommandQueue!
    var mComputePiplineState: MTLComputePipelineState!
    var metalViewDrawableSize: CGSize? = nil
    var targetMetalTextureSize: CGSize = CGSize.zero
    var bufferWidth: Int = -1
    var mTextureBuffer: MTLBuffer?
    
    func setupMetalView() {
        guard let library = self.mDevice?.makeDefaultLibrary() else { return }
        // Register Texture Shader
        guard let kernel = library.makeFunction(name: "computeTexture2d") else { return }
        guard let computePipeline = try? self.mDevice?.makeComputePipelineState(function: kernel) else { return }
        self.mComputePiplineState = computePipeline
        self.metalView.device = self.mDevice
        self.metalView.delegate = self
        self.metalView.framebufferOnly = false // ← これがないとXcode11以降では落ちます
        self.mCommandQueue = self.mDevice?.makeCommandQueue()
        self.log("Success to setup metal view.")
    }
    
    func updateMetalViewDrawableSize() {
        // Viewの実際のフレームサイズから縦横比を参考に高さのドットサイズから幅のドットサイズを求める
        var width = Int(ceil((self.metalView.frame.width/self.metalView.frame.height)*CGFloat(kMetalTextureHeightDotSize)))
        // 書き換えた内容(1) //////
        // 指定するThreadGroupCountで割り切れなければならない為調整をする
        let v: Int = width % kMetalThreadGroupCount
        if v > 0 { width -= v }
        // 書き換えた内容(1) ///////
        self.targetMetalTextureSize = CGSize(width: width, height: kMetalTextureHeightDotSize)
        self.log("drawableSize:\(self.metalView.drawableSize), frame:\(self.metalView.frame) => targetMetalTextureSize:\(self.targetMetalTextureSize) - MetalView")
        self.metalView.drawableSize = self.targetMetalTextureSize
    }
    
    func setupMetalBuffer() {
        guard let device = self.mDevice else { return }
        let colors = [simd_float4].init(repeating: kMetalTextureClearColor, count: self.bufferWidth*kMetalTextureHeightDotSize)
        let bufferLength = colors.count * MemoryLayout<simd_float4>.stride // <- ここ要チェック
        self.mTextureBuffer = device.makeBuffer(bytes: UnsafeRawPointer(colors), length: bufferLength, options: .cpuCacheModeWriteCombined)
    }
    
    func drawCanvas(point: CGPoint) {
        let x: Int = Int(ceil((point.x/self.metalView.frame.width)*CGFloat(self.bufferWidth)))
        let y: Int = Int(ceil((point.y/self.metalView.frame.height)*CGFloat(kMetalTextureHeightDotSize)))
        var color: simd_float4 = [ self.isRed ? 1.0 : 0.0, self.isGreen ? 1.0 : 0.0, self.isBlue ? 1.0 : 0.0, 1.0 ]
        let dataSize = MemoryLayout<simd_float4>.stride
        if let ptr = self.mTextureBuffer?.contents() {
            if 0 <= x, x < self.bufferWidth, 0 <= y, y < kMetalTextureHeightDotSize {
                let index = (x * kMetalTextureHeightDotSize) + y
                self.log("draw color[[\(x), \(y)] => \(index)]: \(color)")
                memcpy(ptr.advanced(by: index*dataSize), &color, dataSize)
            }
        }
        
        // 現在地点と前回地点の間に線を入れます
        var linePoints: [CGPoint] = [CGPoint]()
        let newPoint = CGPoint.init(x: x, y: y)
        defer { self.lastPoint = newPoint } // 前回値を保持しておく
        if let last = self.lastPoint, !last.equalTo(newPoint) {
            // ２点間の線を引く為のポイント一覧を取得し追加する
            linePoints.append(contentsOf: self.getLinePoints(p0: last, p1: newPoint))
        } else {
            // ※同じ点を描画する事になるのであまり処理効率は良く無いですが説明上描画した値を入れます。
            linePoints.append(newPoint)
        }
        
        if self.pointSize > 1 {
            // 円描画
            var cirlePoints: [CGPoint] = [CGPoint]()
            for p in linePoints {
                cirlePoints.append(contentsOf: self.getCircleFillPoints(center: p, radius: self.pointSize/2))
            }
            linePoints.append(contentsOf: cirlePoints)
        }
        
        if linePoints.count > 0, let ptr = self.mTextureBuffer?.contents() {
            for p in linePoints {
                let x = Int(p.x)
                let y = Int(p.y)
                guard x < self.bufferWidth, y < kMetalTextureHeightDotSize else { continue }
                let index = (x * kMetalTextureHeightDotSize) + y
                memcpy(ptr.advanced(by: index*dataSize), &color, dataSize)
            }
        }
    }
    
    // ２点間の線を引く為のポイント一覧を取得する
    // 参考(プレゼンハムのアルゴリズム): https://ja.wikipedia.org/wiki/%E3%83%96%E3%83%AC%E3%82%BC%E3%83%B3%E3%83%8F%E3%83%A0%E3%81%AE%E3%82%A2%E3%83%AB%E3%82%B4%E3%83%AA%E3%82%BA%E3%83%A0
    func getLinePoints(p0: CGPoint, p1: CGPoint) -> [CGPoint] {
        var points = [CGPoint]()
        var x0: Int = Int(p0.x)
        var y0: Int = Int(p0.y)
        let x1: Int = Int(p1.x)
        let y1: Int = Int(p1.y)
        let dx: Int = Int(abs(p1.x - p0.x)) // DeltaX
        let dy: Int = Int(abs(p1.y - p0.y)) // DeltaY
        let sx: Int = (p1.x>p0.x) ? 1 : -1 // StepX
        let sy: Int = (p1.y>p0.y) ? 1 : -1 // StepT
        var err = dx - dy
        while true {
            if x0 >= 0, y0 >= 0 { points.append(CGPoint(x: x0, y: y0)) }
            if x0 == x1, y0 == y1 { break }
            let e2 = 2*err
            if e2 > -dy {
                err -= dy
                x0 += sx
            }
            if e2 < dx {
                err += dx
                y0 += sy
            }
        }
        return points
    }
    
    // 中心点と半径から縁を描く為のポイント一覧を取得する
    // 参考(ブレゼンハム円描画のアルゴリズム): http://dencha.ojaru.jp/programs_07/pg_graphic_09a1.html
    func getCircleFillPoints(center: CGPoint, radius: Int) -> [CGPoint] {
        var points = [CGPoint]()
        
        let centerX: Int = Int(center.x)
        let centerY: Int = Int(center.y)
        var cx: Int = 0
        var cy: Int = radius
        var d: Int = 2 - 2 * radius
        
        // Left Top
        var ltx: Int = 0
        var lty: Int = 0
        // Right Top
        var rtx: Int = 0
        var rty: Int = 0
        // Left Bottom
        var lbx: Int = 0
        var lby: Int = 0
        // Right Bottom
        var rbx: Int = 0
        var rby: Int = 0
        
        // Top(0, R)
        var vx: Int = cx + centerX
        var vy: Int = cy + centerY
        if vx >= 0, vy >= 0 { points.append(CGPoint(x: vx, y: vy)) }
        // Bottom(0, -R)
        vx = cx + centerX
        vy = -cy + centerY
        if vx >= 0, vy >= 0 { points.append(CGPoint(x: vx, y: vy)) }
        // Right(R, 0)
        vx = cy + centerX
        vy = cx + centerY
        if vx >= 0, vy >= 0 { points.append(CGPoint(x: vx, y: vy)) }
        // Left(-R, 0)
        vx = -cy + centerX
        vy = cx + centerY
        if vx >= 0, vy >= 0 { points.append(CGPoint(x: vx, y: vy)) }

        while true {
            if d > -cy {
                cy -= 1
                d += 1 - 2 * cy
            }

            if d <= cx {
                cx += 1
                d += 1 + 2 * cx
            }

            guard cy > 0 else { break }
            
            // Right Bottom (Bottom To Right)
            rbx = cx + centerX
            rby = cy + centerY
            if rbx >= 0, rby >= 0 {
                points.append(CGPoint(x: rbx, y: rby))  // 0 ~ 90
            }
            // Left Bottom (Bottom To Left)
            lbx = -cx + centerX
            lby = cy + centerY
            if lbx >= 0, lby >= 0 {
                points.append(CGPoint(x: lbx, y: lby)) // 90 ~ 180
            }
            // Left Top (Top To Left)
            ltx = -cx + centerX
            lty = -cy + centerY
            if ltx >= 0, lty >= 0 {
               points.append(CGPoint(x: ltx, y: lty))// 180 ~ 270
            }
            // Right Top (Top To Right)
            rtx = cx + centerX
            rty = -cy + centerY
            if rtx >= 0, rty >= 0 {
                points.append(CGPoint(x: rtx, y: rty)) // 270 ~ 360
            }            
            // 上半分は上部分から左右に、下半分はした部分から左右に伸びている
            //print("[\(ltx), \(lty)], [\(rtx), \(rty)], [\(lbx), \(lby)], [\(rbx), \(rby)]")
            // Y軸は左右同じ地点を指している事から上版分、下半分でX軸の左端から右端にポイントを追加する事で円を塗り潰します。
            for i in lbx...rbx {
                if i >= 0, rby >= 0 { points.append(CGPoint(x: i, y: rby)) }
            }
            for i in ltx...rtx {
                if i >= 0, lty >= 0 { points.append(CGPoint(x: i, y: lty)) }
            }
        }
        
        // 中心線
        for i in centerX-radius...centerX+radius {
            if i >= 0, centerY >= 0 { points.append(CGPoint(x: i, y: centerY)) }
        }
        
        return points
    }
    
    //MARK:- MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        self.log("drawableSizeWillChange \(view.drawableSize) => size:\(size), frame:\(self.metalView.frame), targetSize:\(self.targetMetalTextureSize)  - MTKViewDelegate")
        guard !self.targetMetalTextureSize.equalTo(CGSize.zero) else { return }
        if self.metalViewDrawableSize != nil {
            guard !self.metalViewDrawableSize!.equalTo(self.targetMetalTextureSize) else {
                // 前回と同じ値だった場合は更新しない
                return
            }
        }
        self.metalViewDrawableSize = self.targetMetalTextureSize
        self.bufferWidth = Int(self.metalViewDrawableSize!.width)
        self.setupMetalBuffer()
    }
    
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        guard let commandBuffer = self.mCommandQueue.makeCommandBuffer() else { return }
        guard let textureBuffer = self.mTextureBuffer else { return }
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        computeEncoder?.setComputePipelineState(self.mComputePiplineState)
        let texture = drawable.texture
        // 書き込む対象のテクスチャをセット
        computeEncoder?.setTexture(texture, index: 0)
        // GPUに渡すテクスチャ用バッファをセット
        computeEncoder?.setBuffer(textureBuffer, offset: 0, index: 1)
        let threadGroupCount = MTLSizeMake(kMetalThreadGroupCount, kMetalThreadGroupCount, 1)
        let threadGroups = MTLSizeMake(Int(self.targetMetalTextureSize.width) / threadGroupCount.width,
                                       Int(self.targetMetalTextureSize.height) / threadGroupCount.height, 1)
        computeEncoder?.dispatchThreadgroups(threadGroups,
                                             threadsPerThreadgroup: threadGroupCount)        
        computeEncoder?.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    // MARK:- Other
    func log(_ message: String) {
        NSLog(message)
    }
}


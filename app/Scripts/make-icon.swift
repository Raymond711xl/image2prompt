#!/usr/bin/env swift
import AppKit

// 把一张方形原图做成 macOS 的 AppIcon.icns。
//
//   swift Scripts/make-icon.swift [源图] [输出 icns]
//   默认：Resources/AppIcon-source.png → Resources/AppIcon.icns
//
// 为什么不能直接把生图结果丢进 iconutil：
//
// 1. **四角得自己抠掉**。生图模型画的圆角是画上去的，角上那块是不透明的白/底色，
//    不是 alpha。直接用，Dock 和访达里就是四个白角。
//
// 2. **图形只能占 824/1024**。macOS 的图标网格四周留 100px 空白，全出血的图标在 Dock
//    里会比旁边的系统图标明显大一圈——看着不是"更醒目"，是"没做对"。
//
// 3. **圆角是超椭圆不是圆弧**。Apple 那个形状（squircle）的曲率是连续的，用
//    `NSBezierPath(roundedRect:)` 的正圆弧去套，放大看角上会有一处明显的折点。
//
// 原图自带的圆角比 Apple 的方，所以超椭圆蒙版一定落在它内侧，白角会被完整切掉——
// 换一张圆角更圆的源图就不成立了，那种情况得先把源图的圆角磨掉再进来。

let args = CommandLine.arguments
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let src = URL(fileURLWithPath: args.count > 1 ? args[1] : "Resources/AppIcon-source.png",
              relativeTo: root)
let dst = URL(fileURLWithPath: args.count > 2 ? args[2] : "Resources/AppIcon.icns",
              relativeTo: root)

guard let source = NSImage(contentsOf: src) else {
    FileHandle.standardError.write("读不到源图：\(src.path)\n".data(using: .utf8)!)
    exit(1)
}

let canvas: CGFloat = 1024
let art: CGFloat = 824  // Apple 图标网格里圆角方形的边长
let inset = (canvas - art) / 2

/// 超椭圆（squircle）：|x/a|^n + |y/b|^n = 1。n 取 5 是公认最接近 Apple 那个形状的近似。
func squircle(in rect: NSRect, n: CGFloat = 5, steps: Int = 720) -> NSBezierPath {
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let path = NSBezierPath()
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        // 参数式：x = a·sgn(cos t)·|cos t|^(2/n)
        let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
        let y = cy + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        if i == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
    }
    path.close()
    return path
}

/// 主图：1024 透明画布，居中 824 的超椭圆里贴源图
func renderMaster() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.imageInterpolation = .high
    let frame = NSRect(x: inset, y: inset, width: art, height: art)
    squircle(in: frame).addClip()
    source.draw(in: frame, from: NSRect.zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// 从主图缩到目标边长。逐级减半再收尾，直接一步缩到 16px 会把细节抖没。
func scaled(_ master: NSBitmapImageRep, to side: Int) -> Data {
    var current = master
    while current.pixelsWide / 2 > side {
        current = redraw(current, side: current.pixelsWide / 2)
    }
    if current.pixelsWide != side { current = redraw(current, side: side) }
    return current.representation(using: .png, properties: [:])!
}

func redraw(_ rep: NSBitmapImageRep, side: Int) -> NSBitmapImageRep {
    let out = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    NSGraphicsContext.current!.imageInterpolation = .high
    let img = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
    img.addRepresentation(rep)
    img.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
             from: NSRect.zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return out
}

let master = renderMaster()

// iconutil 认死了这套文件名，少一个尺寸它就少一个尺寸，不报错
let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

for (name, side) in entries {
    try scaled(master, to: side).write(to: iconset.appendingPathComponent("\(name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", dst.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }

// 顺手出一张 512 的透明 PNG 给 README 展示用。
// 不复用源图：源图四角是不透明的白，贴进 README 在深色主题下就是四个白角。
let preview = dst.deletingLastPathComponent().appendingPathComponent("AppIcon.png")
try scaled(master, to: 512).write(to: preview)

print("已生成：\(dst.path)\n展示图：\(preview.path)")

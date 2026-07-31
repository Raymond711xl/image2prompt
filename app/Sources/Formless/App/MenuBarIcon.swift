import AppKit

/// 菜单栏图标：斜置的魔法棒 + 左右两颗四角星。
///
/// 为什么手写路径而不是放一张 PNG：菜单栏图标要在 16pt/@1x 和 @2x 之间来回切
/// （拖到外接屏就会发生），位图缩放必糊；而且模板图要求纯黑 + alpha，
/// 位图资源多一道"别人导出时不小心带了灰底"的坑。路径是矢量，系统按需渲染，
/// 顺便省掉一份资源文件和它的打包步骤。
///
/// 曾经用系统的 `wand.and.stars`，中途试过棱镜分光（形是对的，但那是平克·弗洛伊德
/// 那张封面，等于换了个 cliché），最后回到魔法棒，只是自己画、星星按主图标的构图摆。
/// 和主图标共用一套构图：棒从左下往右上斜，星一颗在左上、一颗在右下，对角呼应。
///
/// 尺寸取 16pt：菜单栏高 22pt，系统图标视觉高度基本都在 16–18pt，
/// 再大会顶到上下边缘，再小在拖放时不好瞄准（这个图标同时是投放目标）。
enum MenuBarIcon {
    /// 设计坐标系边长。下面所有点位都按这个尺度写，渲染时整体缩放。
    private static let designSide: CGFloat = 16

    /// 空闲：棒 + 两颗星
    static func idle() -> NSImage { make(busy: false) }

    /// 忙碌：棒尖再冒一颗小星。
    ///
    /// 试过的另外三种都不行：把棒改成空心，16px 下变成一条虚线；把星星换成实心圆点，
    /// 整个图标读成一只哑铃；只把星放大一档，小尺寸下几乎看不出差别。
    /// 加一颗星既保住了轮廓（不会让人以为换了个 App），又正好是"在施法"的意思。
    static func busy() -> NSImage { make(busy: true) }

    private static func make(busy: Bool) -> NSImage {
        let image = NSImage(
            size: NSSize(width: designSide, height: designSide), flipped: false
        ) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.saveGState()
            ctx.translateBy(x: rect.minX, y: rect.minY)
            ctx.scaleBy(x: rect.width / designSide, y: rect.height / designSide)

            // 模板图只看 alpha，颜色由系统按亮/暗菜单栏和高亮态决定，这里画黑即可
            NSColor.black.setStroke()
            NSColor.black.setFill()
            draw(busy: busy)

            ctx.restoreGState()
            return true
        }
        // 关键：置为模板图，深色菜单栏才会自动反白，点中时才会跟随高亮
        image.isTemplate = true
        return image
    }

    private static func draw(busy: Bool) {
        rod(from: NSPoint(x: 4.2, y: 3.4), to: NSPoint(x: 11.4, y: 10.6), width: 2.2)
        // 两颗等大：本来左大右小更有节奏，但 16px 下小的那颗会先糊掉
        sparkle(at: NSPoint(x: 3.0, y: 12.4), radius: 2.3)
        sparkle(at: NSPoint(x: 13.0, y: 4.2), radius: 2.3)
        if busy { sparkle(at: NSPoint(x: 12.9, y: 12.9), radius: 1.7) }
    }

    /// 棒身：圆头粗线。粗于 2.2 会和左上那颗星贴在一起。
    private static func rod(from a: NSPoint, to b: NSPoint, width: CGFloat) {
        let p = NSBezierPath()
        p.move(to: a)
        p.line(to: b)
        p.lineWidth = width
        p.lineCapStyle = .round
        p.stroke()
    }

    /// 四角星：四个尖角 + 内收的腰。
    /// 腰必须用曲线收进去才是 sparkle，直接连四个顶点只会得到一个菱形。
    /// `waist` 取 0.3：再小尖角更利落，但 16px 下星身太细会直接消失。
    private static func sparkle(at c: NSPoint, radius r: CGFloat, waist: CGFloat = 0.30) {
        let w = r * waist
        let p = NSBezierPath()
        p.move(to: NSPoint(x: c.x, y: c.y + r))
        for (end, ctrl) in [
            (NSPoint(x: c.x + r, y: c.y), NSPoint(x: c.x + w, y: c.y + w)),
            (NSPoint(x: c.x, y: c.y - r), NSPoint(x: c.x + w, y: c.y - w)),
            (NSPoint(x: c.x - r, y: c.y), NSPoint(x: c.x - w, y: c.y - w)),
            (NSPoint(x: c.x, y: c.y + r), NSPoint(x: c.x - w, y: c.y + w)),
        ] {
            p.curve(to: end, controlPoint1: ctrl, controlPoint2: ctrl)
        }
        p.close()
        p.fill()
    }
}

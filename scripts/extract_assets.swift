import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit

func saveCGImageAsPNG(_ cgImage: CGImage, to url: URL, targetSize: CGSize? = nil, opaque: Bool = false) -> Bool {
    let width = Int(targetSize?.width ?? CGFloat(cgImage.width))
    let height = Int(targetSize?.height ?? CGFloat(cgImage.height))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo: UInt32 = opaque
        ? CGImageAlphaInfo.noneSkipLast.rawValue
        : CGImageAlphaInfo.premultipliedLast.rawValue

    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        return false
    }

    if opaque {
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    ctx.interpolationQuality = .high
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let outImage = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        return false
    }
    CGImageDestinationAddImage(dest, outImage, nil)
    return CGImageDestinationFinalize(dest)
}

let fm = FileManager.default
let rootDir = URL(fileURLWithPath: fm.currentDirectoryPath)
let carURL = rootDir.appendingPathComponent("scripts/original_Assets.car")
let fallbackIconURL = rootDir.appendingPathComponent("scripts/AppIcon76x76@2x~ipad.png")
let assetsDir = rootDir.appendingPathComponent("nicehck/Assets.xcassets")

// 1. Initialize fallback 1024x1024 PNGs from AppIcon76x76@2x~ipad.png
if let nsImg = NSImage(contentsOf: fallbackIconURL),
   let cgImg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    let appIconOut = assetsDir.appendingPathComponent("AppIcon.appiconset/AppIcon.png")
    _ = saveCGImageAsPNG(cgImg, to: appIconOut, targetSize: CGSize(width: 1024, height: 1024), opaque: true)
    for imgName in ["OriginDetail", "OriginPreview", "originPreview"] {
        let out = assetsDir.appendingPathComponent("\(imgName).imageset/\(imgName).png")
        _ = saveCGImageAsPNG(cgImg, to: out, targetSize: CGSize(width: 512, height: 512), opaque: false)
    }
    print("Prepared fallback PNGs from AppIcon76x76@2x~ipad.png")
}

// 2. Extract full-resolution renditions from original_Assets.car using CoreUI.framework
if let coreUIBundle = Bundle(path: "/System/Library/PrivateFrameworks/CoreUI.framework"),
   coreUIBundle.load(),
   let catalogClass = NSClassFromString("CUICatalog") as? NSObject.Type {
    let initSel = NSSelectorFromString("initWithURL:error:")
    let allocObj = catalogClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject
    if let obj = allocObj, obj.responds(to: initSel) {
        typealias InitWithURLErrorIMP = @convention(c) (AnyObject, Selector, NSURL, UnsafeMutableRawPointer?) -> AnyObject?
        let imp = obj.method(for: initSel)
        let fn = unsafeBitCast(imp, to: InitWithURLErrorIMP.self)
        if let catalog = fn(obj, initSel, carURL as NSURL, nil) as? NSObject {
            var bestImages: [String: CGImage] = [:]
            let cgImgSel = NSSelectorFromString("image")
            let renditionSel = NSSelectorFromString("_rendition")
            let unslicedSel = NSSelectorFromString("unslicedImage")
            typealias CGImageGetterIMP = @convention(c) (AnyObject, Selector) -> Unmanaged<CGImage>?

            let extractCGImage: (NSObject) -> CGImage? = { lookup in
                if lookup.responds(to: cgImgSel) {
                    let getter = unsafeBitCast(lookup.method(for: cgImgSel), to: CGImageGetterIMP.self)
                    if let cg = getter(lookup, cgImgSel)?.takeUnretainedValue() {
                        return cg
                    }
                }
                if lookup.responds(to: renditionSel),
                   let rend = lookup.perform(renditionSel)?.takeUnretainedValue() as? NSObject,
                   rend.responds(to: unslicedSel) {
                    let getter = unsafeBitCast(rend.method(for: unslicedSel), to: CGImageGetterIMP.self)
                    if let cg = getter(rend, unslicedSel)?.takeUnretainedValue() {
                        return cg
                    }
                }
                return nil
            }

            let enumSel = NSSelectorFromString("enumerateNamedLookupsUsingBlock:")
            if catalog.responds(to: enumSel) {
                typealias EnumBlock = @convention(block) (NSObject) -> Void
                typealias EnumIMP = @convention(c) (AnyObject, Selector, AnyObject) -> Void
                let block: EnumBlock = { lookup in
                    guard let name = lookup.value(forKey: "name") as? String,
                          let cg = extractCGImage(lookup) else { return }
                    let pixels = cg.width * cg.height
                    let existingPixels = bestImages[name].map { $0.width * $0.height } ?? 0
                    if pixels > existingPixels {
                        bestImages[name] = cg
                    }
                }
                let enumFn = unsafeBitCast(catalog.method(for: enumSel), to: EnumIMP.self)
                enumFn(catalog, enumSel, unsafeBitCast(block, to: AnyObject.self))
            }

            for (name, cg) in bestImages {
                print("Extracted asset '\(name)' (\(cg.width)x\(cg.height)) from original_Assets.car")
                if name.lowercased().contains("appicon") {
                    let outURL = assetsDir.appendingPathComponent("AppIcon.appiconset/AppIcon.png")
                    _ = saveCGImageAsPNG(cg, to: outURL, targetSize: CGSize(width: 1024, height: 1024), opaque: true)
                } else if name == "OriginDetail" {
                    let out1 = assetsDir.appendingPathComponent("OriginDetail.imageset/OriginDetail.png")
                    _ = saveCGImageAsPNG(cg, to: out1, targetSize: CGSize(width: 1024, height: 1024), opaque: false)
                    if bestImages["OriginPreview"] == nil {
                        let out2 = assetsDir.appendingPathComponent("OriginPreview.imageset/OriginPreview.png")
                        let out3 = assetsDir.appendingPathComponent("originPreview.imageset/originPreview.png")
                        _ = saveCGImageAsPNG(cg, to: out2, targetSize: CGSize(width: 1024, height: 1024), opaque: false)
                        _ = saveCGImageAsPNG(cg, to: out3, targetSize: CGSize(width: 1024, height: 1024), opaque: false)
                    }
                } else if name == "OriginPreview" || name == "originPreview" {
                    let out2 = assetsDir.appendingPathComponent("OriginPreview.imageset/OriginPreview.png")
                    let out3 = assetsDir.appendingPathComponent("originPreview.imageset/originPreview.png")
                    _ = saveCGImageAsPNG(cg, to: out2, targetSize: CGSize(width: 1024, height: 1024), opaque: false)
                    _ = saveCGImageAsPNG(cg, to: out3, targetSize: CGSize(width: 1024, height: 1024), opaque: false)
                }
            }
        }
    }
}

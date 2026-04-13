import Cocoa

extension NSImage {
    /// Combine multiple images with the given blend modes. This is useful given a set
    /// of layers to create a final rasterized image.
    static func combine(images: [NSImage], blendingModes: [CGBlendMode]) -> NSImage? {
        guard images.count == blendingModes.count else { return nil }
        guard images.count > 0 else { return nil }

        // The final size will be the same size as our first image.
        let size = images.first!.size

        // Create a bitmap context manually
        guard let bitmapContext = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Clear the context
        bitmapContext.setFillColor(.clear)
        bitmapContext.fill(.init(origin: .zero, size: size))

        // Draw each image with its corresponding blend mode
        for (index, image) in images.enumerated() {
            guard let cgImage = image.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            ) else { return nil }

            let blendMode = blendingModes[index]
            bitmapContext.setBlendMode(blendMode)
            bitmapContext.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }

        // Create a CGImage from the context
        guard let combinedCGImage = bitmapContext.makeImage() else { return nil }

        // Wrap the CGImage in an NSImage
        return NSImage(cgImage: combinedCGImage, size: size)
    }

    /// Apply a gradient onto this image, using this image as a mask.
    func gradient(colors: [NSColor]) -> NSImage? {
        let resultImage = NSImage(size: size)
        resultImage.lockFocus()
        defer { resultImage.unlockFocus() }

        // Draw the gradient
        guard let gradient = NSGradient(colors: colors) else { return nil }
        gradient.draw(in: .init(origin: .zero, size: size), angle: 90)

        // Apply the mask
        draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1.0)

        return resultImage
    }

    // Tint an NSImage with the given color by applying a basic fill on top of it.
    func tint(color: NSColor) -> NSImage? {
        // Create a new image with the same size as the base image
        let newImage = NSImage(size: size)

        // Draw into the new image
        newImage.lockFocus()
        defer { newImage.unlockFocus() }

        // Set up the drawing context
        guard let context = NSGraphicsContext.current?.cgContext else { return nil }
        defer { context.restoreGState() }

        // Draw the base image
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        context.draw(cgImage, in: .init(origin: .zero, size: size))

        // Set the tint color and blend mode
        context.setFillColor(color.cgColor)
        context.setBlendMode(.sourceAtop)

        // Apply the tint color over the entire image
        context.fill(.init(origin: .zero, size: size))

        return newImage
    }

    func renderedAppIconCanvas(
        canvasSize: CGFloat = 1024,
        insetRatio: CGFloat = 0.14,
        cornerRadiusRatio: CGFloat = 0.22
    ) -> NSImage? {
        let format = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasSize),
            pixelsHigh: Int(canvasSize),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let format else { return nil }

        let result = NSImage(size: NSSize(width: canvasSize, height: canvasSize))
        result.addRepresentation(format)

        result.lockFocus()
        defer { result.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: result.size).fill()

        let inset = canvasSize * insetRatio
        let availableRect = NSRect(
            x: inset,
            y: inset,
            width: canvasSize - (inset * 2),
            height: canvasSize - (inset * 2)
        )
        let fittedRect = fittedRect(in: availableRect)
        let cornerRadius = min(fittedRect.width, fittedRect.height) * cornerRadiusRatio
        let clipPath = NSBezierPath(
            roundedRect: fittedRect,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )

        clipPath.addClip()
        draw(
            in: fittedRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )

        return result
    }

    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func fittedRect(in bounds: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return bounds }

        let imageAspect = size.width / size.height
        let boundsAspect = bounds.width / bounds.height

        if imageAspect > boundsAspect {
            let scaledHeight = bounds.width / imageAspect
            return NSRect(
                x: bounds.minX,
                y: bounds.minY + ((bounds.height - scaledHeight) / 2),
                width: bounds.width,
                height: scaledHeight
            )
        }

        let scaledWidth = bounds.height * imageAspect
        return NSRect(
            x: bounds.minX + ((bounds.width - scaledWidth) / 2),
            y: bounds.minY,
            width: scaledWidth,
            height: bounds.height
        )
    }
}

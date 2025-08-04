Notes
==================

### Capture and export

```swift
Button("Capture and Export") {
    cameraModel.captureTexture { cgImage in
        if let cgImage = cgImage {
            let image = UIImage(cgImage: cgImage)
            if let data = image.pngData() {
                self.imageDataToExport = data
                self.showExport = true
            }
        } else {
            print("Failed to capture image")
        }
    }
}
.sheet(isPresented: $showExport) {
    if let data = imageDataToExport {
        ExportFileView(imageData: data, suggestedName: "CapturedTexture.png")
    }
}
```

### Elapsed frame time average

```swift
var lastDrawTime: CFTimeInterval = 0
var frameIntervals: [Double] = []
let frameSampleCount = 60
        
let now = CACurrentMediaTime()
if lastDrawTime > 0 {
    let delta = (now - lastDrawTime) * 1000  // in milliseconds
    frameIntervals.append(delta)

    if frameIntervals.count == frameSampleCount {
        let average = frameIntervals.reduce(0, +) / Double(frameIntervals.count)
        print(String(format: "debug: frame time over %d frames: %.2f ms (%.2f FPS)", frameSampleCount, average, 1000.0 / average))
        frameIntervals.removeAll()
    }
}
lastDrawTime = now
```
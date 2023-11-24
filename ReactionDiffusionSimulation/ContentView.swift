import CoreImage
import SwiftUI
import AppKit



class ImageGenerator: ObservableObject {
    @Published var image: NSImage?;
    var size: Int = 50;
    var a: Array<Array<Double>>
    var b: Array<Array<Double>>
    var myQueue = DispatchQueue(label: "my.lock.queue")
    var isRunning = true

    init() {
        a = Array(repeating: Array(repeating: 0.0, count: size), count: size)
        b = Array(repeating: Array(repeating: 0.0, count: size), count: size)
    }

    func generateImage(every nthFrame: Int = 3) {
        DispatchQueue.global(qos: .background).async {
            print("Generating image")
            let colorSpace = NSColorSpace.genericRGB
            let bitmapRep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: self.size,
                pixelsHigh: self.size,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: NSColorSpaceName.deviceRGB,
                bytesPerRow: self.size * 4,
                bitsPerPixel: 32)!

            let iterations = 5000
            let eps: Double = 0.0243
            let f: Double = 1.4
            let phi: Double = 0.054
            let q: Double = 0.002
            let Du: Double = 0.45
            let dt: Double = 0.001
            


            for i in 0..<iterations {
                print("Iterating at i=" + String(i))
                guard self.isRunning else { break }

                self.myQueue.sync {
                    var nextA = self.a
                    var nextB = self.b

                    for y in 1..<self.size-1 {
                        for x in 1..<self.size-1 {
                            guard self.isRunning else { return }

                            let u = self.a[y][x]
                            let v = self.b[y][x]

                            let uLaplacian = self.laplacian(self.a, x: x, y: y)
   
                            let du = ((1 / eps) * (u - (u * u) - ((f * v) + phi) * ((u - q) / (u + q))) + Du * uLaplacian)
                            let dv = (u - v)

                            let newU = u + (du * dt)
                            let newV = v + (dv * dt)

                            nextA[y][x] = max(0, min(1, newU))

                            nextB[y][x] = max(0, min(1, newV))
                        }
                    }

                    self.a = nextA
                    self.b = nextB
                }


                if i % nthFrame == 0 {
                    DispatchQueue.main.async {
                        self.image = self.createImage(from: self.a, b: self.b, bitmapRep: bitmapRep, size: self.size)
                    }
                }
                usleep(50)
            }
        }
    }

    private func createImage(from a: [[Double]], b: [[Double]], bitmapRep: NSBitmapImageRep, size: Int) -> NSImage {
        myQueue.async {
            for y in 0..<size {
                for x in 0..<size {
                
                    let r = UInt8(min(max(0, a[y][x]), 1) * 255)
                    let g = UInt8(min(max(0, b[y][x]), 1) * 255)
                    bitmapRep.setColor(NSColor(deviceRed: CGFloat(r)/255.0, green: CGFloat(g)/255.0, blue: 0, alpha: 1.0), atX: x, y: y)
                }
            }
        }
    

        let newImage = NSImage(size: CGSize(width: size, height: size))
        newImage.addRepresentation(bitmapRep)
        return newImage
    }

    private func laplacian(_ grid: [[Double]], x: Int, y: Int) -> Double {
        let u = grid[y][x]
        let adjacentCells = grid[y - 1][x] + grid[y + 1][x] + grid[y][x - 1] + grid[y][x + 1]
        return (adjacentCells - (4 * u)) / (0.25 * 0.25)
    }

}

struct ContentView: View {
    @ObservedObject private var generator: ImageGenerator;
    @State private var dragLocation: CGPoint = .zero  // 1
    init(generator: ImageGenerator) {
        self.generator = generator
        self.generator.generateImage()
    }
    
    var body: some View {
        VStack {
            GeometryReader { mainGeometry in  // 2
                Group {
                    if let img = self.generator.image {
                        Image(nsImage: img)
                            .resizable()
                            .frame(width: mainGeometry.size.width, height: mainGeometry.size.height)
                            .edgesIgnoringSafeArea(.all) // Ensures the image extends out of the safe area in the view
                            .overlay(GeometryReader { geometry in
                                Color.clear
                                    .contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged({ gesture in
                                                    let location = gesture.location
                                                    print(location.x)
                                                    print(geometry.size.width)
                                                    print(geometry.size.height)

                                                    print(generator.size)
                                                    
                                                    let x = Int(location.x / geometry.size.width * CGFloat(generator.size));
                                                    print(x)
                                                    let y = Int(location.y / geometry.size.height * CGFloat(generator.size));
//                                                    self.generator.myQueue.async {
//                                                        
//                                                        self.generator.b[y][x] = 1.0  // Set your desired value here
//                                                    }
//                                                    return;
                                                    if x >= 0 && y >= 0 && x < generator.size && y < generator.size {
                                                        self.generator.myQueue.async {
                                                            // Adjust the radius as needed
                                                            let radius = 5

                                                            // Create a circle around the point
                                                            for dy in -radius...radius {
                                                                for dx in -radius...radius {
                                                                    if dx*dx + dy*dy <= radius*radius {  // Check if the point is within the circle
                                                                        let nx = x + dx
                                                                        let ny = y + dy
                                                                        
                                                                        if (nx >= 0) && (ny >= 0) && (nx < generator.size) && (ny < generator.size) {
                                                                            self.generator.a[ny][nx] = 1.0  // Set your desired value here
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                })
                                        )

                            })
                    } else {
                        Text("Generating Image...")
                    }
                }
            }
        }
    }
}

//
//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView()
//    }
//}

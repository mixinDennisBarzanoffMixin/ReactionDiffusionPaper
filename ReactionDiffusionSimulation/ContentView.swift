import CoreImage
import AppKit
import Metal
import SwiftUI
import MetalKit
import simd

struct VertexOut {
    var position: simd_float4
    var coord: simd_float2
}

class MetalManager {
    var device: MTLDevice
    var texture1: MTLTexture
    var texture2: MTLTexture
    var size: Int
    let library: MTLLibrary
    init() {
        // Initialize device
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = device
        self.size = 50
        guard let library = self.device.makeDefaultLibrary() else {
            fatalError("Error making library")
        }
        self.library = library
        // Create textures
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: self.size,
            height: self.size,
            mipmapped: false
        ) // Define your texture descriptor
        textureDescriptor.usage = [.shaderRead, .shaderWrite]

        texture1 = device.makeTexture(descriptor: textureDescriptor)!
        texture2 = device.makeTexture(descriptor: textureDescriptor)!
    }
    
    func getTextureForRendering() -> MTLTexture {
        return texture1
    }
    func getTextureForComputing() -> MTLTexture {
        return texture2
    }
    func swapTextures() {
        let temp = texture1
        texture1 = texture2
        texture2 = temp
    }

}

class RenderMetalManager {
    var renderPipelineState: MTLRenderPipelineState
    var commandQueue: MTLCommandQueue
    var vertexBuffer: MTLBuffer?

    let metalManager: MetalManager
    init(metalManager: MetalManager) {
        self.metalManager = metalManager
        self.commandQueue = self.metalManager.device.makeCommandQueue()!
        let renderPipeLineDescriptor = MTLRenderPipelineDescriptor()
        renderPipeLineDescriptor.vertexFunction = self.metalManager.library.makeFunction(name: "vertex_main")
        let vertexDescriptor = MTLVertexDescriptor()

        // Position attribute - assuming it's the first attribute
        vertexDescriptor.attributes[0].format = .float4
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        // Texture coordinate attribute - assuming it's the second attribute
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD4<Float>>.size
        vertexDescriptor.attributes[1].bufferIndex = 0
        // Set the stride for the vertex buffer
        vertexDescriptor.layouts[0].stride = MemoryLayout<VertexOut>.stride
        
        renderPipeLineDescriptor.vertexDescriptor = vertexDescriptor
        

        renderPipeLineDescriptor.fragmentFunction = self.metalManager.library.makeFunction(name: "fragment_main")
        renderPipeLineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

//        var vertex = VertexOut(position: simd_float4(1,2,3,1), coord: simd_float2(0.5,0.5))
//        self.buffer = metalManager.device.makeBuffer(bytes: &vertex, length: MemoryLayout<VertexOut>.stride, options: [])!

        do {
            self.renderPipelineState = try self.metalManager.device.makeRenderPipelineState(descriptor: renderPipeLineDescriptor)
        } catch let error {
            fatalError("Error making render pipeline \(error)")
        }
        let quadVertices = [
            VertexOut(position: SIMD4<Float>(-1.0, -1.0, 0.0, 1.0), coord: SIMD2<Float>(0.0, 1.0)), // bottom left
            VertexOut(position: SIMD4<Float>(-1.0,  1.0, 0.0, 1.0), coord: SIMD2<Float>(0.0, 0.0)), // top left
            VertexOut(position: SIMD4<Float>( 1.0, -1.0, 0.0, 1.0), coord: SIMD2<Float>(1.0, 1.0)), // bottom right

//            // Second Triangle
            VertexOut(position: SIMD4<Float>( 1.0, -1.0, 0.0, 1.0), coord: SIMD2<Float>(1.0, 1.0)), // bottom right
            VertexOut(position: SIMD4<Float>(-1.0,  1.0, 0.0, 1.0), coord: SIMD2<Float>(0.0, 0.0)), // top left
            VertexOut(position: SIMD4<Float>( 1.0,  1.0, 0.0, 1.0), coord: SIMD2<Float>(1.0, 0.0))  // top right
        ];
        self.vertexBuffer = self.metalManager.device.makeBuffer(bytes: quadVertices, length: MemoryLayout<VertexOut>.stride * quadVertices.count, options: [])
    }
    func makeRenderPassDescriptor(clearColor: MTLClearColor) -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].clearColor = clearColor
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        return descriptor
    }
}

class BzReactionMetalManager {
    let metalManager: MetalManager
    var commandQueue: MTLCommandQueue
    let pipelineState: MTLComputePipelineState
    


    init(metalManager: MetalManager) {
        self.metalManager = metalManager
        self.commandQueue = metalManager.device.makeCommandQueue()!
        
        let defaultLibrary = metalManager.device.makeDefaultLibrary()
        let kernelFunction = defaultLibrary?.makeFunction(name: "bz_compute")
        let pipelineStateDescriptor = MTLComputePipelineDescriptor()
        pipelineStateDescriptor.computeFunction = kernelFunction
        self.pipelineState = try! metalManager.device.makeComputePipelineState(descriptor: pipelineStateDescriptor, options: [], reflection: nil);
    }
    func compute(iteration: Int) {
        usleep(200)
        let texture1 = metalManager.texture1
        let texture2 = metalManager.texture2
        if let commandBuffer = self.commandQueue.makeCommandBuffer(),
                let commandEncoder = commandBuffer.makeComputeCommandEncoder()  {

            commandEncoder.setTexture(self.metalManager.getTextureForComputing(), index: 1)
            commandEncoder.setTexture(self.metalManager.getTextureForRendering(), index: 0)

            if (iteration.isMultiple(of: 2)) {
                self.metalManager.swapTextures()
            }
            
            let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
            let textureWidth = texture1.width;
            let textureHeight = texture1.height;
            let threadgroupsPerGridWidth = (textureWidth + threadgroupSize.width - 1) / threadgroupSize.width
            let threadgroupsPerGridHeight = (textureHeight + threadgroupSize.width - 1) / threadgroupSize.height
            let threadgroupsPerGrid = MTLSize(width: threadgroupsPerGridWidth, height: threadgroupsPerGridHeight, depth: 1)
            commandEncoder.setComputePipelineState(self.pipelineState)

            commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadgroupSize)
            commandEncoder.endEncoding()
            commandBuffer.commit()
        }

    }
}

class Renderer: NSObject, MTKViewDelegate {
    var renderMetalManager: RenderMetalManager?

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {

        if let device = MTLCreateSystemDefaultDevice() {
            view.device = device
        }

    }
    func draw(in view: MTKView) {
        
        if (view.device == nil) {
            print("device nil")
        }
        if (view.currentDrawable == nil) {
            print("Drawable nil")
        }
        guard let renderMetalManager = self.renderMetalManager else { return }

        guard let commandBuffer = renderMetalManager.commandQueue.makeCommandBuffer() else {
            print("Command buffer creation failed")
            return
        }

        let renderPassDescriptor = renderMetalManager.makeRenderPassDescriptor(clearColor: MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1))
        renderPassDescriptor.colorAttachments[0].texture = view.currentDrawable!.texture
        
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
//        guard let commandBuffer = renderMetalManager.commandQueue.makeCommandBuffer(),
//              let renderPassDescriptor = view.currentRenderPassDescriptor,
//              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
//            return
//        }
        print("drawing")


        
        renderEncoder.setRenderPipelineState(renderMetalManager.renderPipelineState)

        // Bind the texture used by the compute shader
        renderEncoder.setFragmentTexture(renderMetalManager.metalManager.getTextureForRendering(), index: 0)
        // Create a sampler descriptor
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .nearest
        samplerDescriptor.magFilter = .nearest

        // Create a sampler state using the descriptor and device
        if let samplerState = renderMetalManager.metalManager.device.makeSamplerState(descriptor: samplerDescriptor) {
            renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        }
        // Set vertex data (assuming you have a method to get this)
        let vertexBuffer = renderMetalManager.vertexBuffer
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
    
        // Issue a draw call
        renderEncoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 6) // Set vertexCount appropriately

        // End encoding
        renderEncoder.endEncoding()

        // Present and commit the command buffer
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()

    }
}

class TextureView: MTKView {
    var renderer: Renderer!

    func configure(renderMetalManager: RenderMetalManager) {
        renderer = Renderer()
        renderer.renderMetalManager = renderMetalManager
        self.delegate = renderer
    }

}

struct MetalViewRepresentable: NSViewRepresentable {
    typealias UIViewType = MTKView
    var renderMetalManager: RenderMetalManager
    
    func makeNSView(context: Context) -> MTKView {
        let mtkView = TextureView()
        mtkView.configure(renderMetalManager: renderMetalManager)
        return mtkView
    }
    
    func updateNSView(_ uiView: MTKView, context: Context) {
        // Update the view if necessary
        print("updating view")
    }
}
    
    
    
class ImageGenerator: ObservableObject {
    @Published var image: NSImage?;
    var size: Int = 50;
    var myQueue = DispatchQueue(label: "my.lock.queue")
    var isRunning = true
    let bzReactionManager: BzReactionMetalManager
    
    init(bzReactionManager: BzReactionMetalManager) {
        self.bzReactionManager = bzReactionManager
    }
    
    func generateImage(every nthFrame: Int = 3) {
        DispatchQueue.global(qos: .background).async {
            print("Generating image")
            
            
            let iterations = 5000
            
            for i in 0..<iterations {
//                print("Iterating at i=" + String(i))
                guard self.isRunning else { break }
                self.myQueue.sync {
                    self.bzReactionManager.compute(iteration: i)

                }

                usleep(50)
            }
            print("Finished")
        }
    }
}
    
struct ContentView: View {
    @State private var dragLocation: CGPoint = .zero  // 1
    let onOffNotifier: OnOffNotifier
    
    
    private let metalManager: MetalManager
    private let bzReactionManager: BzReactionMetalManager
    private let renderManager: RenderMetalManager
    private let generator: ImageGenerator
    
    init(onOffNotifier: OnOffNotifier) {
        self.onOffNotifier = onOffNotifier
        self.metalManager = MetalManager()
        self.bzReactionManager = BzReactionMetalManager(metalManager: self.metalManager)
        self.renderManager = RenderMetalManager(metalManager: self.metalManager)
        self.generator = ImageGenerator(bzReactionManager: self.bzReactionManager)
//        self.startRenderingLoop()
    }
    
    // Existing properties...

//    var timer: Timer?

//    func startRenderingLoop() {
//        self.timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
//            self?.refreshView()
//        }
//    }
//    private func refreshView() {
//        DispatchQueue.main.async {
//            // Assuming you have a reference to your TextureView instance
//            textureView.setNeedsDisplay()
//        }
//    }

    var body: some View {
         GeometryReader { mainGeometry in  // 2
                MetalViewRepresentable(renderMetalManager: self.renderManager)
                    .frame(width: mainGeometry.size.width, height: mainGeometry.size.height)
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
                                                // Create a circle around the point
                                                setRadius(centerX: 5, centerY: 10, radius: 10)
                                            }
                                        }
                                    })
                            )
                        
                    })

            }.onAppear {
                self.generator.generateImage()
            }.navigationTitle("BZ Reaction")
                .frame(maxWidth: .infinity)
                .edgesIgnoringSafeArea([.leading, .bottom, .trailing])
        
    }
    func setRadius(centerX: UInt32, centerY: UInt32, radius: UInt32) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Unable to create a Metal device.")
        }

        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Unable to create a command queue.")
        }

        let color: [Float] = [1.0, 0.0, 0.0, 1.0]
        var center = uint2(centerX, centerY)
        var radiusR = radius
        let centerBuffer = device.makeBuffer(bytes: &center, length: MemoryLayout<uint2>.stride, options: [])
        let radiusBuffer = device.makeBuffer(bytes: &radiusR, length: MemoryLayout<uint>.stride, options: [])
        let colorBuffer = device.makeBuffer(bytes: color, length: color.count * MemoryLayout<Float>.stride, options: [])

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            fatalError("Unable to create a command buffer.")
        }

        guard let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
            fatalError("Unable to create a command encoder.")
        }

        let library = device.makeDefaultLibrary()!
        let computeFunction = library.makeFunction(name: "set_color")!

        var computePipelineState: MTLComputePipelineState? = nil
        do {
            computePipelineState = try device.makeComputePipelineState(function: computeFunction)
        } catch {
          print("Failed to create compute pipeline state: \(error)")
        }

        commandEncoder.setComputePipelineState(computePipelineState!)

        commandEncoder.setBuffer(centerBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(radiusBuffer, offset: 0, index: 1)
        commandEncoder.setBuffer(colorBuffer, offset: 0, index: 2)
        
        let texture = self.generator.bzReactionManager.metalManager.getTextureForComputing()
        
        commandEncoder.setTexture(texture, index: 0)

        let threadGroupCount = MTLSizeMake(1, 1, 1)
        let threadGroups = MTLSize(width: (texture.width + threadGroupCount.width - 1) / threadGroupCount.width,
                                   height: (texture.height + threadGroupCount.height - 1) / threadGroupCount.height,
                                   depth: 1)
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)

        commandEncoder.endEncoding()
        commandBuffer.commit()
    }

    func debugReadData(commandBuffer: MTLCommandBuffer) {
        let bytesPerRow = metalManager.texture1.width * 4 // 4 bytes per pixel for RGBA
        let alignedBytesPerRow = ((bytesPerRow + 15) / 16) * 16 // Align to 16 bytes
        let bufferSize = bytesPerRow * metalManager.texture1.height
        guard let cpuBuffer = metalManager.device.makeBuffer(length: bufferSize, options: .storageModeShared) else { return }
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            fatalError("Could not create blit encoder")
        }

        blitEncoder.synchronize(resource: metalManager.texture1)
        blitEncoder.copy(from: metalManager.texture1,
                         sourceSlice: 0,
                         sourceLevel: 0,
                         sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                         sourceSize: MTLSize(width: metalManager.texture1.width, height: metalManager.texture1.height, depth: 1),
                         to: cpuBuffer,
                         destinationOffset: 0,
                         destinationBytesPerRow: alignedBytesPerRow,
                         destinationBytesPerImage: bufferSize)

        blitEncoder.endEncoding()
        commandBuffer.addCompletedHandler { _ in
            let data = Data(bytesNoCopy: cpuBuffer.contents(), count: bufferSize, deallocator: .none)
            // Process data here...
        }
        commandBuffer.commit()

    }
}

//
//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView()
//    }
//}

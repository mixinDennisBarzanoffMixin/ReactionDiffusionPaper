
import Metal
import CoreImage
import AppKit
import Metal
import SwiftUI
import MetalKit
import simd

struct BrushState {
    var color: float4 = [1, 0, 0, 1]
    var center: uint2 = [50, 50]
    var radius: UInt32 = 100
    var enabled = false
    
    mutating func setRadius(centerX: UInt32, centerY: UInt32, radius: UInt32) {
        self.center = uint2(x: centerX, y: centerY)
        self.radius = radius
        self.enabled = true
    }
    
}

let size = 50

var GlobalBrushState = BrushState() // This gets updated from the UI


class MetalService {
    static let shared = MetalService()

    // Metal properties
    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    var texture1: MTLTexture?
    var texture2: MTLTexture?
    
    var texture: MTLTexture? {
        get {
            return texture1
        }
    }
    
    func swapTexture() {
        let temp = texture1
        texture1 = texture2
        texture2 = temp
    }
    

    // Initializer
    private init?() {
        // Get the device
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.device = device

        // Create the command queue
        guard let commandQueue = device.makeCommandQueue() else { return nil }
        self.commandQueue = commandQueue
        self.texture1 = setupWithDrawingTexture(width: size, height: size)
        self.texture2 = setupWithDrawingTexture(width: size, height: size)
    }

    func setupWithDrawingTexture(width: Int, height: Int) -> MTLTexture? {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]

        let texture = device.makeTexture(descriptor: textureDescriptor)

        return texture
    }
}


class BrushModifier {

    private let device: MTLDevice
    private let texture: MTLTexture
    private let computePipelineState: MTLComputePipelineState
    
    init?() {
        self.device = MetalService.shared!.device
        self.texture = MetalService.shared!.texture!

        // Set up the compute pipeline state with the given shader function name
        guard let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "set_color"),
              let computePipelineState = try? device.makeComputePipelineState(function: function) else {
            return nil
        }

        self.computePipelineState = computePipelineState
    }
    
    func draw() {
        if (!GlobalBrushState.enabled) {
            return;
        }
        let device = MetalService.shared!.device
        var color = GlobalBrushState.color
        var center = GlobalBrushState.center
        var radiusR = GlobalBrushState.radius
        let centerBuffer = device.makeBuffer(bytes: &center, length: MemoryLayout<uint2>.stride, options: [])
        let radiusBuffer = device.makeBuffer(bytes: &radiusR, length: MemoryLayout<uint>.stride, options: [])
        let colorBuffer = device.makeBuffer(bytes: &color, length: MemoryLayout<SIMD4<Float>>.stride, options: [])

        guard let commandBuffer = MetalService.shared!.commandQueue.makeCommandBuffer() else {
            fatalError("Unable to create a command buffer.")
        }
        commandBuffer.label = "Brush command buffer"


        guard let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
            fatalError("Unable to create a command encoder.")
        }
        // waits for the compute to finish at the beginning // first is compute, then brush
//        commandEncoder.waitForFence(self.MetalService.shared!.computeFence)


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
        
        let texture = MetalService.shared!.texture!
        
        commandEncoder.setTexture(texture, index: 0)

        let threadGroupCount = MTLSizeMake(1, 1, 1)
        let threadGroups = MTLSize(width: (texture.width + threadGroupCount.width - 1) / threadGroupCount.width,
                                   height: (texture.height + threadGroupCount.height - 1) / threadGroupCount.height,
                                   depth: 1)
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)

        commandEncoder.endEncoding()
//        commandEncoder.updateFence(self.MetalService.shared!.brushFence)
//        commandEncoder.waitForFence(self.MetalService.shared!.renderFence)
        
        // barrier, brush and render can execute concurrently

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        GlobalBrushState.enabled = false
    }

}

struct VertexOut {
    var position: simd_float4
    var coord: simd_float2
}

class BzReaction {
    var commandQueue: MTLCommandQueue
    let pipelineState: MTLComputePipelineState

    init() {
        self.commandQueue = MetalService.shared!.commandQueue
        
        let defaultLibrary = MetalService.shared!.device.makeDefaultLibrary()
        let kernelFunction = defaultLibrary?.makeFunction(name: "bz_compute")
        let pipelineStateDescriptor = MTLComputePipelineDescriptor()
        pipelineStateDescriptor.computeFunction = kernelFunction
        self.pipelineState = try! MetalService.shared!.device.makeComputePipelineState(descriptor: pipelineStateDescriptor, options: [], reflection: nil);
    }
    func compute(iteration: Int) {
//        return
        let texture1 = MetalService.shared!.texture1!
        let texture2 = MetalService.shared!.texture2!
        if let commandBuffer = self.commandQueue.makeCommandBuffer(),
                let commandEncoder = commandBuffer.makeComputeCommandEncoder()  {
            commandBuffer.label = "Compute command buffer"
            commandEncoder.setTexture(texture2, index: 1)
            commandEncoder.setTexture(texture1, index: 0)
            
            let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
            let textureWidth = texture1.width;
            let textureHeight = texture2.height;
            let threadgroupsPerGridWidth = (textureWidth + threadgroupSize.width - 1) / threadgroupSize.width
            let threadgroupsPerGridHeight = (textureHeight + threadgroupSize.width - 1) / threadgroupSize.height
            let threadgroupsPerGrid = MTLSize(width: threadgroupsPerGridWidth, height: threadgroupsPerGridHeight, depth: 1)
            commandEncoder.setComputePipelineState(self.pipelineState)

            commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadgroupSize)
            commandEncoder.endEncoding()
//            commandEncoder.updateFence(MetalService.shared!.computeFence)
//            commandEncoder.waitForFence(MetalService.shared!.renderFence)
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            // both the rendering and the computation are finished
            
            
            
        }

    }
}


class Renderer: NSObject, MTKViewDelegate {
    let brush: BrushModifier
    let reaction: BzReaction
    var pipelineState: MTLRenderPipelineState!
    let samplerState: MTLSamplerState
    override init() {
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        // Set your shaders in the pipeline
        let library = MetalService.shared!.device.makeDefaultLibrary()!
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        // Set your pipeline's pixel formats to match your drawable's pixel format
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        self.brush = BrushModifier()!
        self.reaction = BzReaction()

        // Compile the pipeline state
        pipelineState = try! MetalService.shared!.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        
        // Setup a default sampler
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge

        samplerState = MetalService.shared!.device.makeSamplerState(descriptor: samplerDescriptor)!
        

    }

    func draw(in view: MTKView) {
        brush.draw()
        reaction.compute(iteration: 1)
        guard let drawable = view.currentDrawable else { return }

        // Create vertex buffer
        let quadVertices = [
            VertexOut(position: SIMD4<Float>(-1.0, -1.0, 0.0, 1.0), coord: SIMD2<Float>(0.0, 1.0)), // bottom left
            VertexOut(position: SIMD4<Float>(-1.0,  1.0, 0.0, 1.0), coord: SIMD2<Float>(0.0, 0.0)), // top left
            VertexOut(position: SIMD4<Float>( 1.0, -1.0, 0.0, 1.0), coord: SIMD2<Float>(1.0, 1.0)), // bottom right

//            // Second Triangle
            VertexOut(position: SIMD4<Float>( 1.0, -1.0, 0.0, 1.0), coord: SIMD2<Float>(1.0, 1.0)), // bottom right
            VertexOut(position: SIMD4<Float>(-1.0,  1.0, 0.0, 1.0), coord: SIMD2<Float>(0.0, 0.0)), // top left
            VertexOut(position: SIMD4<Float>( 1.0,  1.0, 0.0, 1.0), coord: SIMD2<Float>(1.0, 0.0))  // top right
        ];
        let vertexBuffer = MetalService.shared!.device.makeBuffer(bytes: quadVertices, length: MemoryLayout<VertexOut>.stride * quadVertices.count, options: [])
        let commandBuffer = MetalService.shared!.commandQueue.makeCommandBuffer()!
        if let renderPassDescriptor = view.currentRenderPassDescriptor, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setFragmentTexture(MetalService.shared!.texture, index: 0)
            renderEncoder.setFragmentSamplerState(samplerState, index: 0) // Set the sampler state here

            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: quadVertices.count)
            renderEncoder.endEncoding()
            
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        MetalService.shared?.swapTexture()
    }

    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    private weak var mtkView: MTKView?


}


struct MetalNSView: NSViewRepresentable {
    let mtkView: MTKView

    func makeNSView(context: Context) -> MTKView {
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // performing updates of your `nsView` if needed
    }
}




struct ContentView: View {
    let mtkView: MTKView

    var renderer: Renderer?
    init() {
        self.renderer = Renderer()
        self.mtkView = MTKView()
        self.mtkView.delegate = self.renderer
        self.mtkView.device = MetalService.shared?.device
        self.mtkView.framebufferOnly = false

    }
    var body: some View {
        GeometryReader { mainGeometry in  // 2
            MetalNSView(mtkView: mtkView)
                .frame(width: mainGeometry.size.width, height: mainGeometry.size.height)
                .overlay(GeometryReader { geometry in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged({ gesture in
                                    let location = gesture.location
                                    
                                    let x = Int(location.x / geometry.size.width * CGFloat(size));
                                    print(x)
                                    let y = Int(location.y / geometry.size.height * CGFloat(size));
                                    if x >= 0 && y >= 0 && x < size && y < size {
                                        GlobalBrushState.setRadius(centerX: UInt32(x), centerY: UInt32(y), radius: 5)
                                    }
                                })
                        )
                    
                })
            
        }.navigationTitle("BZ Reaction")
            .frame(maxWidth: .infinity)
            .edgesIgnoringSafeArea([.leading, .bottom, .trailing])
    }
}

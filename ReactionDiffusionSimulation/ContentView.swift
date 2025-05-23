
import Metal
import CoreImage
import AppKit
import Metal
import SwiftUI
import MetalKit
import simd
import MetalPerformanceShaders


var globalDebugValue: Float = 0.0

struct BrushState {
    var color: float4 = [1, 0, 0, 1]
    var center: uint2?
    var radius: UInt32 = 10
    var pulsingLocations: [CGPoint] = []
    var enabled = true
    
    mutating func setRadius(centerX: UInt32, centerY: UInt32, radius: UInt32) {
        self.center = uint2(x: centerX, y: centerY)
        self.radius = radius
        self.enabled = true
    }

//    mutating func addPulsingLocation(_ x: UInt32, y: UInt32) {
//        // Check if location is already in the list
//        for existingLocation in pulsingLocations {
//            let distance = sqrt(pow(existingLocation.x - x, 2) + pow(existingLocation.y - y, 2))
//            if CGFloat(radius) > distance {
//                // Location is close to an existing location, remove the existing location
//                pulsingLocations.removeAll { $0 == existingLocation }
//                return
//            }
//        }
//        // Location is not in the list, add it
//        pulsingLocations.append(CGPoint { x: x, y: y })
//    }
    
}

struct Seed {
    var seed1: UInt32 = 0
    var seed2: UInt32 = 0
}

struct ReactionConfig {
    var seed: Seed = Seed()
    var noiseScale: Float32 = 0;
    var phi_passive: Float32 = 0.0975; // will change before experiments
}

var GlobalReactionConfig = ReactionConfig()

var GlobalBrushState = BrushState() // This gets updated from the UI


class MetalService {
    static let shared = MetalService()
    // Metal properties
    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    var texture1: MTLTexture?
    var texture2: MTLTexture?
    var computeFence: MTLFence?
    
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
        self.texture1 = setupWithDrawingTexture()
        self.texture2 = setupWithDrawingTexture()
        self.computeFence = device.makeFence()
    }


    func setupWithDrawingTexture() -> MTLTexture? {
        
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        
        // Load the image as a new texture.
        let loader = MTKTextureLoader(device: device)

        guard let url = Bundle.main.url(forResource: "circuit2", withExtension: "png") else { return nil }
        guard let texture = try? loader.newTexture(URL: url, options: nil) else { return nil }
        
        // Create a destination texture with the required pixel format.
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float,
                                                                  width: texture.width,
                                                                  height: texture.height,
                                                                  mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let destTexture = device.makeTexture(descriptor: descriptor) else { return nil }
        
        if let commandBuffer = device.makeCommandQueue()?.makeCommandBuffer() {
            
            let mpsConversion = MPSImageConversion(device: device,
                                                   srcAlpha: .alphaIsOne,
                                                   destAlpha: .alphaIsOne,
                                                   backgroundColor: nil,
                                                   conversionInfo: nil)
            
            mpsConversion.encode(commandBuffer: commandBuffer, sourceTexture: texture, destinationTexture: destTexture)
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }

        return destTexture
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
        commandEncoder.waitForFence(MetalService.shared!.computeFence!)
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
        
        let texture = MetalService.shared!.texture2!
        
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
//        commandBuffer.waitUntilCompleted()
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
    var experimentManager: ExperimentManager
    var phiPassive: Float
    // We need this to track the tick() because this code controls the tick speed
    init(experimentManager: ExperimentManager, phiPassive: Float) {
        self.phiPassive = phiPassive
        self.experimentManager = experimentManager
        self.commandQueue = MetalService.shared!.commandQueue
        
        let defaultLibrary = MetalService.shared!.device.makeDefaultLibrary()
        let kernelFunction = defaultLibrary?.makeFunction(name: "bz_compute")
        let pipelineStateDescriptor = MTLComputePipelineDescriptor()
        pipelineStateDescriptor.computeFunction = kernelFunction
        self.pipelineState = try! MetalService.shared!.device.makeComputePipelineState(descriptor: pipelineStateDescriptor, options: [], reflection: nil);
    }
    func updatePhiPassive(phiPassive: Float) {
        self.phiPassive = phiPassive
    }
    func compute(iteration: Int) {
//        return;

        usleep(300)
        experimentManager.tick()

        let texture1 = MetalService.shared!.texture1!
        let texture2 = MetalService.shared!.texture2!
        if let commandBuffer = self.commandQueue.makeCommandBuffer(),
                let commandEncoder = commandBuffer.makeComputeCommandEncoder()  {
            commandBuffer.label = "Compute command buffer"
            let seedNum1 = UInt32.random(in: .min ... .max)
            let seedNum2 = UInt32.random(in: .min ... .max)

            var seed = Seed(seed1: seedNum1, seed2: seedNum2);
            GlobalReactionConfig.seed = seed
            var config = GlobalReactionConfig
            //print(GlobalReactionConfig.noiseScale)
            
            let seedBuffer = commandBuffer.device.makeBuffer(bytes: &config, length: MemoryLayout<ReactionConfig>.stride, options: [])
            let x = GlobalBrushState.center?.x ?? 0;
            let y = GlobalBrushState.center?.y ?? 0;
            var debugInputLocation = SIMD2<UInt32>(x: UInt32(x), y: UInt32(y)) // Modify as per your requirement
            var debugValue: Float = 0.0

            let debugInputBuffer = commandBuffer.device.makeBuffer(bytes: &debugInputLocation,
                                                                   length: MemoryLayout<SIMD2<UInt32>>.size,
                                                                   options: []);
            let debugValueBuffer = commandBuffer.device.makeBuffer(length: MemoryLayout<Float>.size,
                                                                   options: [])

            commandEncoder.setBuffer(debugInputBuffer, offset: 0, index: 1)
            commandEncoder.setBuffer(debugValueBuffer, offset: 0, index: 2)

//            print("hashes")
//            print(texture1.hash)
//            print(texture2.hash)
            commandEncoder.setTexture(texture1, index: 1)
            commandEncoder.setTexture(texture2, index: 0)
            commandEncoder.setBuffer(seedBuffer, offset: 0, index: 0)
            
            let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
            let textureWidth = texture1.width;
            let textureHeight = texture1.height;
            let threadgroupsPerGridWidth = (textureWidth + threadgroupSize.width - 1) / threadgroupSize.width
            let threadgroupsPerGridHeight = (textureHeight + threadgroupSize.width - 1) / threadgroupSize.height
            let threadgroupsPerGrid = MTLSize(width: threadgroupsPerGridWidth, height: threadgroupsPerGridHeight, depth: 1)
            commandEncoder.setComputePipelineState(self.pipelineState)

            commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadgroupSize)
            commandEncoder.endEncoding()
            commandEncoder.updateFence(MetalService.shared!.computeFence!)
//            commandEncoder.waitForFence(MetalService.shared!.renderFence)
            commandBuffer.addCompletedHandler{ _ in
                let debugOutput = debugValueBuffer?.contents().assumingMemoryBound(to: Float.self)
                guard debugOutput != nil else {return}
                debugValue = debugOutput!.pointee
                globalDebugValue = debugValue
//                print("Debug Value: \(debugValue)")
            }
            commandBuffer.commit()
            
            
            // both the rendering and the computation are finished
        }

    }
}

class Renderer: NSObject, MTKViewDelegate {
    let brush: BrushModifier
    let reaction: BzReaction
    var pipelineState: MTLRenderPipelineState!
    let samplerState: MTLSamplerState
    let experimentManager: ExperimentManager
    override init() {
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        // Set your shaders in the pipeline
        let library = MetalService.shared!.device.makeDefaultLibrary()!
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        // Set your pipeline's pixel formats to match your drawable's pixel format
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        self.brush = BrushModifier()!

        // Compile the pipeline state
        pipelineState = try! MetalService.shared!.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        
        // Setup a default sampler
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge

        samplerState = MetalService.shared!.device.makeSamplerState(descriptor: samplerDescriptor)!
        
        let width = MetalService.shared!.texture1!.width;
        let height = MetalService.shared!.texture1!.height;
//        let variables: [Float] = [
////            0.0905069, 0.09141196, 0.09232608, 0.09324935, 0.09418184, 0.09512366,
////            0.09555, // Explicit inclusion of phi_min for clarity
////            0.09578887, 0.09602835, 0.09626842, 0.09650909, 0.09675036, 0.09699224,
////            0.09723472, 0.09747781, 0.0977215,
////            0.106127, // Explicit inclusion of phi_max for clarity
////            0.10639232, 0.1066583, 0.10692494, 0.10719226, 0.10746024, 0.10772889,
////            0.10799821, 0.10826821, 0.10853888
//            0.106127
//        ]
//        let variables: [Float] = [
//            0.10559636, 0.10570249, 0.10580862, 0.10591475, 0.10602087,
//            0.106127,   // The central focus value
//            0.10623313, 0.10633925, 0.10644538, 0.10655151, 0.10665764
//        ]

        let variables: [Float] = [
//            0.0975,
            0.106129965120
//            0.106120, 0.106121, 0.106122, 0.106123, 0.106124, 0.106125, 0.106126, 0.106127, 0.106128, 0.106129
            
        ]


        let tempExperimentManager = ExperimentManager(
            start: SIMD2<UInt32>(210, 157),
            end: SIMD2<UInt32>(137, 157),
            width: UInt32(width),
            height: UInt32(height),
            device: MetalService.shared!.device,
            variables: variables,
            callback: nil) // Temporarily set callback to nil to break the circular dependency

        self.reaction = BzReaction(experimentManager: tempExperimentManager, phiPassive: variables[0])

        tempExperimentManager.variableUpdateCallback = { newValue in
            GlobalReactionConfig.phi_passive = newValue
        }

        self.experimentManager = tempExperimentManager
    }
    
//    static func getImageCoords(x: Float, y: Float) -> SIMD2<Float> {Â
//        return SIMD2<Float>(x/Float(MetalService.shared!.texture1!.width),y/Float(MetalService.shared!.texture1!.height))
//    }
    static func getImageCoords(x: Float, y: Float) -> SIMD2<Float> {
        let nx = 2.0 * (x / Float(MetalService.shared!.texture1!.width)) - 1.0
        let ny = 2.0 * (y / Float(MetalService.shared!.texture1!.height)) - 1.0
        return SIMD2<Float>(nx, ny)
    }
    
    func startReaction() {
        DispatchQueue.global().async {
            while (true) {
                self.reaction.compute(iteration: 1)
                MetalService.shared?.swapTexture()
            }
        }
    }

    func draw(in view: MTKView) {
        experimentManager.startExperimentIfNeeded()

        brush.draw()
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
            renderEncoder.setFragmentTexture(MetalService.shared!.texture2, index: 0)
            renderEncoder.setFragmentSamplerState(samplerState, index: 0) // Set the sampler state here

            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: quadVertices.count)
            experimentManager.draw(encoder: renderEncoder, in: view)

            renderEncoder.endEncoding()

            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
        experimentManager.checkAndEndExperimentIfNeeded(texture: MetalService.shared!.texture1!)


//        commandBuffer.waitUntilCompleted()
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


struct ConfigView: View {
    @State private var isOn = false
    @State private var value: Float = 0

    var body: some View {
        VStack(alignment: .leading) {
//            Toggle(isOn: $isOn) {
//                Text("Toggle")
//                    .foregroundColor(.black)
//            }
            Slider(value: Binding(
                get: { self.value },
                set: { newValue in
                    self.value = newValue
                    self.sliderChanged(newValue: newValue)
                }
            ), in: 0...1) {
                Text("Noise slider")
                    .foregroundColor(.black)
            }
            .padding()
        }
        .padding()
        .background(Color.white)
        .cornerRadius(10)
    }
    
    func sliderChanged(newValue: Float) {
        print("Setting slider value to \(value)")
        GlobalReactionConfig.noiseScale = Float32(newValue)
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
        self.renderer?.startReaction()

    }

    var body: some View {
        GeometryReader { mainGeometry in  // 2
            ZStack {
                MetalNSView(mtkView: mtkView)
                    .frame(width: mainGeometry.size.width, height: mainGeometry.size.height)
                    .overlay(GeometryReader { geometry in
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged({ gesture in
//                                        self.renderer?.experimentManager.forceExperimentStart();
//                                        return;
                                        let location = gesture.location
                                        guard let width = MetalService.shared!.texture1?.width else { return }
                                        guard let height = MetalService.shared!.texture1?.height else { return }
                                        let x = Int(location.x / geometry.size.width * CGFloat(width));
                                        let y = Int(location.y / geometry.size.height * CGFloat(height));
                                        if x >= 0 && y >= 0 && x < width && y < height {
                                            GlobalBrushState.setRadius(centerX: UInt32(x), centerY: UInt32(y), radius: 5)
                                        }
                                    })
                            )
                            .onTapGesture {
//                                self.renderer?.experimentManager.forceExperimentStart();
//                                return;
                                let location = $0
                                guard let width = MetalService.shared!.texture1?.width else { return }
                                guard let height = MetalService.shared!.texture1?.height else { return }
                                let x = Int(location.x / geometry.size.width * CGFloat(width));
                                let y = Int(location.y / geometry.size.height * CGFloat(height));
                                if x >= 0 && y >= 0 && x < width && y < height {
                                    GlobalBrushState.setRadius(centerX: UInt32(x), centerY: UInt32(y), radius: 5)
                                    // GlobalBrushState.addPulsingLocation(x, y)
                                }
                            }
                        
                    })
                
            }.navigationTitle("BZ Reaction")
                .frame(maxWidth: .infinity)
                .edgesIgnoringSafeArea([.leading, .bottom, .trailing])
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack {
                Spacer()
                HStack {
//                    ConfigView()
//                        .frame(maxWidth: mainGeometry.size.width / 3)
//                        .padding()
                    Spacer()
                }
            }
        }
    }
}

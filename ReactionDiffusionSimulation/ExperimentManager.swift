//
//  ExperimentManager.swift
//  ReactionDiffusionSimulation
//
//  Created by Dennis Barzanoff on 22.12.23.
//

import Foundation
import Metal
import simd
import MetalKit

class ExperimentManager {
    private var startPosition: SIMD2<UInt32>
    private var endPosition: SIMD2<UInt32>
    private var startTime: DispatchTime?
    private var endTime: DispatchTime?
    private var commandQueue: MTLCommandQueue!
    private var shader: MTLComputePipelineState!
    private var device: MTLDevice
    private var experimentHasStarted = false
    private var experimentEnabled = true
    let cooldownDuration: TimeInterval = 2.0

    private var cooldownStartTime: Date?

    var flagStartTexture: MTLTexture?
    var flagEndTexture: MTLTexture?


    init(start: SIMD2<UInt32>, end: SIMD2<UInt32>, device: MTLDevice) {
        self.startPosition = start
        self.endPosition = end
        self.device = device
        guard let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "samplingShader") else {
            fatalError("Unable to create the compute state")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Unable to create command queue")
        }
        self.commandQueue = commandQueue
        
        do {
            self.shader = try device.makeComputePipelineState(function: function)
        } catch {
            fatalError("Unable to create pipeline state: \(error)")
        }
        flagStartTexture = loadTexture(imageName: "startFlag", ext: "png")
        flagEndTexture = loadTexture(imageName: "endFlag", ext: "png")

    }
    
    func validateState() {
        // can't have started and not enabled
        guard (experimentEnabled || !experimentHasStarted) else {
            fatalError("Invalid state: experiment started, but not enabled");
        }
    }
    
    func startExperimentIfNeeded() {
        validateState();
        if let cooldownStartTime = cooldownStartTime {
            if Date().timeIntervalSince(cooldownStartTime) < cooldownDuration {
                return
            }
        }
        // Irrespective of what the above condition says, the cooldown time is definitely over once we get here.
        cooldownStartTime = nil

        // Only start the experiment if it hasn't already begun
        guard !experimentHasStarted else { return }
        // Set the global brush state
        GlobalBrushState.center = startPosition
        GlobalBrushState.enabled = true
        experimentHasStarted = true
        startTime = DispatchTime.now()
    }
    
    func checkAndEndExperimentIfNeeded(texture: MTLTexture) {
        validateState();
        guard experimentHasStarted else { return }
        
        let color = sampleColor(position: endPosition, texture: texture)
        
        // Check if wave has arrived
        if isWaveColor(color) {
            endTime = DispatchTime.now()
                
            if let start = startTime, let end = endTime {
                // Calculate execution time
                let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
                let timeInterval = Double(nanoTime) / 1_000_000_000
                print("Execution time: \(String(format: "%.3f",timeInterval)) sec")

                // Reset the experiment state
                resetExperiment()
            }
        }
    }

    private func resetExperiment() {
        experimentHasStarted = false
        startTime = nil
        endTime = nil
        cooldownStartTime = Date()
    }


    func endExperiment(texture: MTLTexture) {
        let colorEnd = sampleColor(position: endPosition, texture: texture)
        
        // If the color signifies the end of the wave and the timer has started, stop the timer
        if isWaveColor(colorEnd), let startTime = self.startTime {
            self.endTime = DispatchTime.now()
            calculateTimeDifference(startTime: startTime, endTime: self.endTime)
            self.startTime = nil
        }
    }
    private func sampleColor(position: SIMD2<UInt32>, texture: MTLTexture) -> SIMD4<Float> {
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let computeCommandEncoder = commandBuffer.makeComputeCommandEncoder()!

        computeCommandEncoder.setComputePipelineState(shader)

        // Pass position to the shader
        var pos = uint2(UInt32((position.x)), UInt32((position.y)))
        computeCommandEncoder.setBytes(&pos, length: MemoryLayout<SIMD2<UInt32>>.size, index: 0)

        // Pass texture to the shader
        computeCommandEncoder.setTexture(texture, index: 0)

        // Allocate a memory for a single SIMD4<Float>
        let outputBuffer = device.makeBuffer(length: MemoryLayout<SIMD4<Float>>.size, options: [])
        
        computeCommandEncoder.setBuffer(outputBuffer, offset: 0, index: 1)

        let threadsPerGroup = MTLSizeMake(1, 1, 1)
        let numThreadgroups = MTLSizeMake(1, 1, 1)

        computeCommandEncoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
        computeCommandEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Read color data from buffer
        let colorData = outputBuffer!.contents().assumingMemoryBound(to: SIMD4<Float>.self)
        //print("RED: " + String(colorData.pointee.x))
        return colorData.pointee
    }


    
    private func isWaveColor(_ color: SIMD4<Float>) -> Bool {
        // Check if the pixel's color indicates the presence of the wave
        return color.x > 0.2;
    }
    
    private func calculateTimeDifference(startTime: DispatchTime, endTime: DispatchTime?) {
        guard let endTime = endTime else { return }
        let nanoTime = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let timeInterval = Double(nanoTime) / 1_000_000_000
        print("Execution time: \(String(format: "%.3f",timeInterval)) sec")
    }
    private func createQuadVertices(center: SIMD2<Float>, size: SIMD2<Float> = SIMD2<Float>(0.02, 0.02)) -> [VertexOut] {
        let halfSize = size / 2.0

        let topLeft = SIMD2<Float>(center.x - halfSize.x, center.y + halfSize.y)
        let topRight = SIMD2<Float>(center.x + halfSize.x, center.y + halfSize.y)
        let bottomLeft = SIMD2<Float>(center.x - halfSize.x, center.y - halfSize.y)
        let bottomRight = SIMD2<Float>(center.x + halfSize.x, center.y - halfSize.y)

        return [
          VertexOut(position: SIMD4<Float>(topRight.x, topRight.y, 0.0, 1.0), coord: SIMD2<Float>(1.0, 0.0)),      // Top Right
          VertexOut(position: SIMD4<Float>(topLeft.x, topLeft.y, 0.0, 1.0), coord: SIMD2<Float>(0.0, 0.0)),        // Top Left
          VertexOut(position: SIMD4<Float>(bottomRight.x, bottomRight.y, 0.0, 1.0), coord: SIMD2<Float>(1.0, 1.0)),// Bottom Right
          VertexOut(position: SIMD4<Float>(bottomLeft.x, bottomLeft.y, 0.0, 1.0), coord: SIMD2<Float>(0.0, 1.0)),  // Bottom Left
        ]
    }


    func drawFlag(renderEncoder: MTLRenderCommandEncoder, flagTexture: MTLTexture, position: SIMD2<UInt32>, view: MTKView) {
        // Prepare your command encoder and set up your commands
        renderEncoder.setFragmentTexture(flagTexture, index: 0)
        // Calculate normalized coordinates
        let normalizedPos = Renderer.getImageCoords(x: Float(position.x), y: Float(position.y))
        var quadVertices = createQuadVertices(center: normalizedPos)
        let vertexBuffer = MetalService.shared!.device.makeBuffer(bytes: &quadVertices, length: MemoryLayout<VertexOut>.stride * quadVertices.count, options: [])
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: quadVertices.count)
        
    }

    func draw(encoder renderEncoder: MTLRenderCommandEncoder, in view: MTKView) {
        // Draw start flag
        drawFlag(renderEncoder: renderEncoder, flagTexture: flagStartTexture!, position: startPosition, view: view)

        // Draw end flag
        drawFlag(renderEncoder: renderEncoder, flagTexture: flagEndTexture!, position: endPosition, view: view)

    }

}

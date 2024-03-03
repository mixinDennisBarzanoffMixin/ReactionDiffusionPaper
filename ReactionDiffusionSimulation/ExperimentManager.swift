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
    let cooldownDuration: DispatchTimeInterval = DispatchTimeInterval.seconds(1)

    private var cooldownStartTime: DispatchTime?

    var flagStartTexture: MTLTexture?
    var flagEndTexture: MTLTexture?

    private var width: UInt32
    private var height: UInt32

    private var experimentVariable: Float
    private var experimentVariableInitial: Float
    private var experimentVariableInterval: Float
    private var numberOfPoints: Int
    private var currentRun: Int = 0
    private var tickCounts: [Int] = []
     var variableUpdateCallback: ((Float) -> Void)?

    init(start: SIMD2<UInt32>, end: SIMD2<UInt32>, width: UInt32, height: UInt32, device: MTLDevice, variable: Float, interval: Float, points: Int, callback: ((Float) -> Void)? = nil) {
        self.width = width
        self.height = height
        self.startPosition = start
        self.endPosition = end
        self.device = device
        self.experimentVariable = variable
        self.experimentVariableInitial = variable
        self.experimentVariableInterval = interval
        self.numberOfPoints = points
        self.variableUpdateCallback = callback
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
    private var currentExperimentIndex: Int = 0
    private var currentIterationIndex: Int = 0
        
    func validateState() {
        // can't have started and not enabled
        if experimentHasStarted && !experimentEnabled {
            fatalError("Invalid state: experiment started, but not enabled");
        }
    }
    private var tickCounter: Int = 0
    
    func tick() {
        if !experimentHasStarted { return }

        tickCounter += 1
    }
    
    func inCooldown(currentTime: DispatchTime) -> Bool {

        if let cooldownStartTime = cooldownStartTime {
            //print("Cooldown start time exists")
            let cooldownEndTimeAfterStart = cooldownStartTime.advanced(by: cooldownDuration)
            //print("Cooldown end time after start: \(cooldownEndTimeAfterStart)")
            let cooldownEndTimeAfterEnd = endTime?.advanced(by: cooldownDuration)
            //print("Cooldown end time after end: \(String(describing: cooldownEndTimeAfterEnd))")
            if currentTime < cooldownEndTimeAfterStart {
//                print("Current time is before cooldown end time after start")
                return true
            } else if cooldownEndTimeAfterEnd != nil && currentTime < cooldownEndTimeAfterEnd! {
//                print("Current time is before cooldown end time after end")
                return true
            }
        }
        return false
    }
    
    func startExperimentIfNeeded() {
        guard experimentEnabled else { return }
        let currentTime = DispatchTime.now()
        if self.inCooldown(currentTime: currentTime) { return }
        validateState();
        //print("Checking cooldown conditions")

//        print("No cooldown conditions met")
        
        // Only start the experiment if it hasn't already begun
        forceExperimentStart()
    }
    
    func forceExperimentStart() {

        if let variableUpdateCallback = variableUpdateCallback {
            let midpointAdjustment = (Float(numberOfPoints) / 2) * experimentVariableInterval

            // Determine the direction and amount of adjustment based on the currentExperimentIndex
            // This example assumes you want to increment from the midpoint
            let adjustment = Float(currentExperimentIndex - (numberOfPoints / 2)) * experimentVariableInterval
            
            experimentVariable = experimentVariableInitial + adjustment

            // Notify about the variable change
            variableUpdateCallback(experimentVariable)

        }

        startTime = nil
        endTime = nil
        cooldownStartTime = DispatchTime.now()
        tickCounter = 0
        GlobalBrushState.center = SIMD2<UInt32>(startPosition.x, height - startPosition.y)
        GlobalBrushState.enabled = true
        experimentHasStarted = true
        startTime = DispatchTime.now()
    }
    
    func checkAndEndExperimentIfNeeded(texture: MTLTexture) {
        validateState()
        guard experimentHasStarted else { return }
        
        // Inverting Y axis to match coordinate system used elsewhere
        let invertedYPosition = SIMD2<UInt32>(endPosition.x, height - endPosition.y)
        let color = sampleColor(position: invertedYPosition, texture: texture)
        
        // Check if wave has arrived
        if isWaveColor(color) {
            endTime = DispatchTime.now()
            //print("Ending experiment")
            endExperiment(texture: texture)
            
            // Increment the iteration index
            currentIterationIndex += 1

            // Check if all iterations for the current experiment are done
            if currentIterationIndex >= 7 { // Assuming 5 iterations per experiment
                currentIterationIndex = 0
                currentExperimentIndex += 1
                print("Run \(currentExperimentIndex) with phi_passive = \(self.experimentVariable) ended")

                // Check if all experiments are done
                if currentExperimentIndex >= numberOfPoints {
                    // All experiments completed
                    // Reset or handle completion
                    currentExperimentIndex = 0 // Reset or set a flag indicating completion
                    // Optionally, handle the completion of all experiments here
                    print("Experiment finished")
                    experimentEnabled = false
                }
            }
        }
    }


    func endExperiment(texture: MTLTexture) {
        // Inverting Y axis to match coordinate system used elsewhere
        let invertedEndPosition = SIMD2<UInt32>(endPosition.x, height - endPosition.y)
        let colorEnd = sampleColor(position: invertedEndPosition, texture: texture)
        
        // If the color signifies the end of the wave and the timer has started, stop the timer
        if isWaveColor(colorEnd), let startTime = self.startTime {
            self.endTime = DispatchTime.now()
            adjustTicksForAnimationSpeed()
            self.startTime = nil
            self.tickCounter = 0
            self.experimentHasStarted = false; // will start it again
        }
    }
    
//    private let animationSpeedFactor: Double = 0.001 // Since 0.0002/0.001 = 2, to adjust for slower animation speed. Comes from the BZ reaction code.
    // dt = 0.0002
    
    private func adjustTicksForAnimationSpeed() {
//        print("Unadjusted ticks: \(tickCounter)")
//        print("Animation speed factor: \(animationSpeedFactor)")
        let adjustedTicks = Int(tickCounter)
        print("Propagation time: \(adjustedTicks) ticks")
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


//
//  Util.swift
//  ReactionDiffusionSimulation
//
//  Created by Dennis Barzanoff on 23.12.23.
//

import Foundation
import Metal
import MetalKit

func loadTexture(imageName: String, ext: String) -> MTLTexture? {
    
    guard let device = MTLCreateSystemDefaultDevice() else { return nil }
    
    // Load the image as a new texture.
    let loader = MTKTextureLoader(device: device)
    // use the 'Bundle' API to access the contents of your app bundle
    guard let url = Bundle.main.url(forResource:imageName, withExtension: ext) else {
        print("Failed to find path for resource named: \(imageName)")
        return nil
    }
//    let textureLoaderOptions: [MTKTextureLoader.Option : Any] = [.origin : MTKTextureLoader.Origin.bottomLeft]
    do {
        let texture = try loader.newTexture(URL: url, options: nil)
        return texture
    } catch {
        print("Failed to create texture from image: \(error)")
        return nil
    }
}

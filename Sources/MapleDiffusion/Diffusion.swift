import Foundation
import Combine
import CoreGraphics
import CoreImage

/**
 
 This is the package's wrapper for the `MapleDiffusion` class. It adds a few convenient ways to use @madebyollin's code.
 
 */

public class Diffusion : ObservableObject {
    
    /// Current state of the models. Only supports states for loading currently, updated via `initModels`
    public var state = PassthroughSubject<GeneratorState, Never>()
    
    @Published public var isModelReady = false
    @Published public var loadingProgress : Double = 0.0
    
    var modelIsCold : Bool {
        print("coldness: ", isModelReady, loadingProgress)
        return !isModelReady && loadingProgress == 0 }
    
    var mapleDiffusion : MapleDiffusion!
    
    // Local, offline Stable Diffusion generation in Swift, no Python. Download + init + generate = 1 line of code.
    
    
    public static var shared = Diffusion()
    
    
    // TODO: Move to + generate
    // TODO: Add steps, guiadance etc as optional params
    public static func generate(localOrRemote modelURL: URL, prompt: String) async throws -> CGImage? {
        
        if shared.modelIsCold {
            if modelURL.isFileURL {
                try await shared.prepModels(localUrl: modelURL)
            } else {
                try await shared.prepModels(remoteURL: modelURL)
            }
        }
        return await shared.generate(input: SampleInput(prompt: prompt))
    }
    
    private var saveMemory = false

    public init(saveMemoryButBeSlower: Bool = false) {
        self.saveMemory = saveMemoryButBeSlower
        state.send(.notStarted)
    }

    /// Empty publisher for convenience in SwiftUI (since you can't listen to a nil)
    public static var placeholderPublisher : AnyPublisher<GenResult,Never> { PassthroughSubject<GenResult,Never>().eraseToAnyPublisher() }
    

    
    // Prep models
    
    
    /// Tuple type for easier access to the progress while also getting the full state.
    public typealias LoaderUpdate = (progress: Double, state: GeneratorState)
    
    /// Init models and update publishers. Run this off the main actor.
    /// TODO: 3 overloads: local only, remote only, both - build into arguments what they do
    var combinedProgress : Double = 0
    
    
    public func prepModels(localUrl: URL, progress:((Double)->Void)? = nil) async throws {
        let fetcher = ModelFetcher(local: localUrl)
        try await initModels(fetcher: fetcher, progress: progress)
    }
    
    public func prepModels(remoteURL: URL, progress:((Double)->Void)? = nil) async throws {
        let fetcher = ModelFetcher(remote: remoteURL)
        try await initModels(fetcher: fetcher, progress: progress)
    }
    
    public func prepModels(localUrl: URL, remoteUrl: URL, progress:((Double)->Void)? = nil) async throws {
        let fetcher = ModelFetcher(local: localUrl, remote: remoteUrl)
        try await initModels(fetcher: fetcher, progress: progress)
    }
    
    
    // Init Models
    
    
    private func initModels(
        fetcher: ModelFetcher,
        progress: ((Double)->Void)?
    ) async throws {
        let combinedSteps : Double = 2
        var combinedProgress : Double = 0
        
        await MainActor.run {
            self.loadingProgress = 0.05
        }
        
        /// 1. Fetch the model
        let modelLocation: URL = try await fetcher.fetch { p in
            combinedProgress = (p/combinedSteps)
            self.updateLoadingProgress(progress: combinedProgress, message: "Fetching models")
        }
        
        /// 2. instantiate MD, which has light side effects
        self.mapleDiffusion = MapleDiffusion(modelLocation: modelLocation, saveMemoryButBeSlower: saveMemory)
        
        let earlierProgress = combinedProgress
        
        /// 3. Initialize models on a background thread
//        try await initModels() { p in
//            combinedProgress = (p/combinedSteps) + earlierProgress
//            self.updateLoadingProgress(progress: combinedProgress, message: "Loading models")
//            progress?(combinedProgress)
//        }
        
        /// 4. Done. Set published main status to true
        await MainActor.run {
            print("Model is ready")
            self.state.send(.ready)
            self.loadingProgress = 1
            self.isModelReady = true
        }
    }
    
    private func updateLoadingProgress(progress: Double, message:String) {
        Task {
            await MainActor.run {
                self.state.send(GeneratorState.modelIsLoading(progress: progress, message: message))
                self.loadingProgress = progress
            }
        }
    }
}

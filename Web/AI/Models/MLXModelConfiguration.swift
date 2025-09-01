import Foundation

/// Configuration for MLX models with Hugging Face integration
struct MLXModelConfiguration {
    let name: String
    let modelId: String
    let huggingFaceRepo: String  // Hugging Face repository identifier
    let cacheDirectoryName: String  // Cache directory name format
    let estimatedSizeGB: Double
    let modelKey: String

    // Llama 3.2 1B 4-bit configuration (MLX optimized)
    static let llama3_2_1B_4bit = MLXModelConfiguration(
        name: "Llama 3.2 1B 4-bit (MLX)",
        modelId: "llama3_2_1B_4bit",
        huggingFaceRepo: "mlx-community/Llama-3.2-1B-Instruct-4bit",
        cacheDirectoryName: "models--mlx-community--Llama-3.2-1B-Instruct-4bit",
        estimatedSizeGB: 0.8,  // 1B model is smaller
        modelKey: "llama3_2_1B_4bit"
    )

    // Llama 3.2 3B 4-bit configuration (larger option)
    static let llama3_2_3B_4bit = MLXModelConfiguration(
        name: "Llama 3.2 3B 4-bit (MLX)",
        modelId: "llama3_2_3B_4bit",
        huggingFaceRepo: "mlx-community/Llama-3.2-3B-Instruct-4bit",
        cacheDirectoryName: "models--mlx-community--Llama-3.2-3B-Instruct-4bit",
        estimatedSizeGB: 1.9,
        modelKey: "llama3_2_3B_4bit"
    )

    // Gemma 2 2B 4-bit configuration (high quality, compact)
    static let gemma3_2B_4bit = MLXModelConfiguration(
        name: "Gemma 2 2B 4-bit (MLX)",
        modelId: "gemma3_2B_4bit",
        huggingFaceRepo: "mlx-community/gemma-2-2b-it-4bit",
        cacheDirectoryName: "models--mlx-community--gemma-2-2b-it-4bit",
        estimatedSizeGB: 1.4,
        modelKey: "gemma3_2B_4bit"
    )

    // Gemma 2 9B 4-bit configuration (highest quality)
    static let gemma3_9B_4bit = MLXModelConfiguration(
        name: "Gemma 2 9B 4-bit (MLX)",
        modelId: "gemma3_9B_4bit",
        huggingFaceRepo: "mlx-community/gemma-2-9b-it-4bit",
        cacheDirectoryName: "models--mlx-community--gemma-2-9b-it-4bit",
        estimatedSizeGB: 5.2,
        modelKey: "gemma3_9B_4bit"
    )
}

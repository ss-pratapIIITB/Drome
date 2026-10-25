import Foundation
import Hub
import MLX
import MLXNN
import Tokenizers

struct LayaClassificationResponse: Sendable {
    let safe: Bool
    let reason: String
    let confidence: Double
    let latencyMs: Double
}

enum LayaMLXError: LocalizedError {
    case invalidConfiguration(String)
    case missingSpecialToken(String)
    case invalidModelOutput

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): message
        case .missingSpecialToken(let token): "Laya tokenizer is missing \(token)"
        case .invalidModelOutput: "Laya returned an invalid decision"
        }
    }
}

actor LayaMLXRuntime {
    static let shared = LayaMLXRuntime()

    static let modelID = "aac6fef/laya-mlx"
    static let modelSizeBytes = 842_609_225

    private var agent: LayaAgent?
    private var loadingTask: Task<LayaAgent, Error>?
    private(set) var loadSummary: String?

    func prepare(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        _ = try await loadAgent(progress: progress)
    }

    func classify(_ text: String) async throws -> LayaClassificationResponse {
        let responses = try await classifyBatch([text])
        guard let first = responses.first else { throw LayaMLXError.invalidModelOutput }
        return first
    }

    func classifyBatch(_ texts: [String]) async throws -> [LayaClassificationResponse] {
        guard !texts.isEmpty else { return [] }
        try Task.checkCancellation()
        let agent = try await loadAgent()
        try Task.checkCancellation()
        let responses = try agent.classifyBatch(texts)
        try Task.checkCancellation()
        return responses
    }

    private func loadAgent(
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> LayaAgent {
        if let agent { return agent }
        if let loadingTask { return try await loadingTask.value }

        let task = Task<LayaAgent, Error> {
            try await LayaAgent.load(modelID: Self.modelID, progress: progress)
        }
        loadingTask = task

        do {
            let loaded = try await task.value
            agent = loaded
            loadSummary = loaded.loadSummary
            loadingTask = nil
            return loaded
        } catch {
            loadingTask = nil
            throw error
        }
    }
}

private struct LayaEncoderConfiguration: Decodable, Sendable {
    struct RopeConfiguration: Decodable, Sendable {
        let ropeTheta: Float

        enum CodingKeys: String, CodingKey {
            case ropeTheta = "rope_theta"
        }
    }

    let vocabSize: Int
    let hiddenSize: Int
    let intermediateSize: Int
    let numHiddenLayers: Int
    let numAttentionHeads: Int
    let normEpsilon: Float
    let normBias: Bool
    let attentionBias: Bool
    let mlpBias: Bool
    let localAttention: Int
    let layerTypes: [String]
    let ropeParameters: [String: RopeConfiguration]

    enum CodingKeys: String, CodingKey {
        case vocabSize = "vocab_size"
        case hiddenSize = "hidden_size"
        case intermediateSize = "intermediate_size"
        case numHiddenLayers = "num_hidden_layers"
        case numAttentionHeads = "num_attention_heads"
        case normEpsilon = "norm_eps"
        case normBias = "norm_bias"
        case attentionBias = "attention_bias"
        case mlpBias = "mlp_bias"
        case localAttention = "local_attention"
        case layerTypes = "layer_types"
        case ropeParameters = "rope_parameters"
    }

    var headDimension: Int { hiddenSize / numAttentionHeads }

    func ropeBase(for attentionType: String) -> Float {
        ropeParameters[attentionType]?.ropeTheta
            ?? (attentionType == "full_attention" ? 160_000 : 10_000)
    }

    func validate() throws {
        guard hiddenSize % numAttentionHeads == 0, headDimension % 2 == 0 else {
            throw LayaMLXError.invalidConfiguration("ModernBERT requires an even attention head dimension")
        }
        guard layerTypes.count == numHiddenLayers else {
            throw LayaMLXError.invalidConfiguration("ModernBERT layer count does not match its configuration")
        }
    }
}

private struct LayaAgentConfiguration: Decodable, Sendable {
    let headLayers: Int
    let maxLength: Int
    let headMaxLength: Int
    let temperatures: [Float]
    let temperaturesByOptions: [String: Float]

    enum CodingKeys: String, CodingKey {
        case headLayers = "head_layers"
        case maxLength = "max_len"
        case headMaxLength = "head_max_len"
        case temperatures = "temperature"
        case temperaturesByOptions = "temperature_by_options"
    }
}

private struct LayaQuestion: Sendable {
    enum Kind: String, Sendable {
        case choice
        case score
        case noul

        var index: Int32 {
            switch self {
            case .choice: 0
            case .score: 1
            case .noul: 2
            }
        }
    }

    struct Option: Sendable {
        let label: String
        let description: String

        var rendered: String {
            description.isEmpty ? label : "\(label): \(description)"
        }
    }

    let kind: Kind
    let instructions: String
    let options: [Option]
}

private struct LayaPreparedItem: Sendable {
    let ids: [Int32]
    let markerPositions: [Int32]
    let questionType: Int32
}

private final class LayaAgent: @unchecked Sendable {
    // 8-bit affine quantization of the linear stack. Embeddings, norms and
    // biases stay FP16: they are a small share of the checkpoint and their
    // kernels are latency-neutral, while every transformer/head matmul gets
    // MLX's int8 path and roughly half the weight traffic.
    private static let quantizationBits = 8
    private static let quantizationGroupSize = 64
    private static var quantizationEnabled: Bool {
        // Default ON when the key has never been set.
        UserDefaults.standard.object(forKey: "aiQuantizeModel") as? Bool ?? true
    }

    private static let unsafeQuestion = LayaQuestion(
        kind: .noul,
        instructions: "Would this web content likely trigger anxiety or be unsafe because it contains violence, death, self-harm, crime, disaster, a health crisis, financial doom, adult content, outrage bait, alarming claims, or high-pressure urgency?",
        options: [
            .init(label: "false", description: "no, the statement does not hold"),
            .init(label: "true", description: "yes, the statement holds"),
        ]
    )

    private static let categoryQuestion = LayaQuestion(
        kind: .choice,
        instructions: "Which content-safety category best describes this web content?",
        options: [
            .init(label: "safe", description: "neutral, educational, entertaining, practical, or ordinary content"),
            .init(label: "violence", description: "violence, death, crime, war, terrorism, or disaster"),
            .init(label: "self_harm", description: "suicide, self-harm, overdose, or severe mental-health crisis"),
            .init(label: "adult", description: "nudity, pornography, or explicit sexual content"),
            .init(label: "health_crisis", description: "alarming disease, outbreak, injury, or medical emergency"),
            .init(label: "financial_stress", description: "recession, layoffs, bankruptcy, or financial doom"),
            .init(label: "urgency", description: "high-pressure demand, fear-inducing warning, or act-now language"),
            .init(label: "outrage", description: "rage bait, scandal, inflammatory claim, or alarming statistic"),
        ]
    )

    private static let reasons = [
        "safe": "Safe content",
        "violence": "Violence or crisis",
        "self_harm": "Self-harm content",
        "adult": "Adult content",
        "health_crisis": "Health crisis",
        "financial_stress": "Financial stress",
        "urgency": "Urgency pressure",
        "outrage": "Outrage or alarm",
    ]

    private let tokenizer: any Tokenizer
    private let model: LayaDecisionModel
    private let configuration: LayaAgentConfiguration
    let loadSummary: String
    private let clsTokenID: Int32
    private let separatorTokenID: Int32
    private let paddingTokenID: Int32
    private let maskTokenID: Int32

    private init(
        tokenizer: any Tokenizer,
        model: LayaDecisionModel,
        configuration: LayaAgentConfiguration,
        loadSummary: String
    ) throws {
        self.tokenizer = tokenizer
        self.model = model
        self.configuration = configuration
        self.loadSummary = loadSummary

        guard let cls = tokenizer.convertTokenToId("[CLS]") else {
            throw LayaMLXError.missingSpecialToken("[CLS]")
        }
        guard let separator = tokenizer.convertTokenToId("[SEP]") else {
            throw LayaMLXError.missingSpecialToken("[SEP]")
        }
        guard let padding = tokenizer.convertTokenToId("[PAD]") else {
            throw LayaMLXError.missingSpecialToken("[PAD]")
        }
        guard let mask = tokenizer.convertTokenToId("[MASK]") else {
            throw LayaMLXError.missingSpecialToken("[MASK]")
        }
        clsTokenID = Int32(cls)
        separatorTokenID = Int32(separator)
        paddingTokenID = Int32(padding)
        maskTokenID = Int32(mask)
    }

    static func load(
        modelID: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> LayaAgent {
        let directory = try await HubApi.shared.snapshot(
            from: modelID,
            matching: [
                "model.safetensors",
                "rl_agent_config.json",
                "encoder/config.json",
                "tokenizer/*.json",
            ]
        ) { value in
            progress(value.fractionCompleted)
        }

        let decoder = JSONDecoder()
        let encoderConfiguration = try decoder.decode(
            LayaEncoderConfiguration.self,
            from: Data(contentsOf: directory.appending(path: "encoder/config.json"))
        )
        try encoderConfiguration.validate()
        let agentConfiguration = try decoder.decode(
            LayaAgentConfiguration.self,
            from: Data(contentsOf: directory.appending(path: "rl_agent_config.json"))
        )

        let tokenizer = try await AutoTokenizer.from(
            modelFolder: directory.appending(path: "tokenizer")
        )
        let model = LayaDecisionModel(
            encoderConfiguration: encoderConfiguration,
            headLayerCount: agentConfiguration.headLayers
        )

        var weights = try loadArrays(url: directory.appending(path: "model.safetensors"))
        weights.removeValue(forKey: "temperature")
        weights = weights.filter { key, _ in !key.hasPrefix("act_head.") }
        try model.update(
            parameters: ModuleParameters.unflattened(weights),
            verify: .all
        )
        weights.removeAll()
        eval(model.parameters())

        let activeMB = Double(Memory.activeMemory) / 1_048_576
        let peakMB = Double(Memory.peakMemory) / 1_048_576
        let loadSummary: String
        if Self.quantizationEnabled {
            let quantizeStarted = ContinuousClock.now
            // mlx-swift's `Module.update(modules:)` cannot rewire a module
            // array whose first element is unchanged: unflattening fills the
            // gap with `.none` and the internal `try!` traps. Encoder and head
            // arrays are uniformly updated, but the scorer is a Sequential
            // that starts with a LayerNorm, so it is rebuilt explicitly.
            var quantizedLayers = Self.quantizeSubtree(model.encoder)
            quantizedLayers += Self.quantizeSubtree(model.head)
            quantizedLayers += Self.quantizeScorer(of: model)
            eval(model.parameters())
            Memory.clearCache()
            let quantizeMs = Self.milliseconds(since: quantizeStarted)
            loadSummary = String(
                format: "Laya int%d · %d layers quantized in %.0f ms · %.0f MB active (peak %.0f MB)",
                Self.quantizationBits,
                quantizedLayers,
                quantizeMs,
                activeMB,
                peakMB
            )
        } else {
            loadSummary = String(
                format: "Laya FP16 · %.0f MB active (peak %.0f MB)",
                activeMB,
                peakMB
            )
        }
        print("[Laya] \(loadSummary)")

        Memory.cacheLimit = 64 * 1024 * 1024
        return try LayaAgent(
            tokenizer: tokenizer,
            model: model,
            configuration: agentConfiguration,
            loadSummary: loadSummary
        )
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1e15
    }

    /// Quantizes every `Linear` below `module` in one module-update pass.
    /// Returns the number of layers replaced (0 when the subtree is skipped).
    @discardableResult
    private static func quantizeSubtree(_ module: Module) -> Int {
        let updates: [(String, Module)] = module.leafModules()
            .flattened()
            .compactMap { path, leaf in
                guard let linear = leaf as? Linear,
                      linear.weight.dim(-1) % quantizationGroupSize == 0,
                      let quantized = quantizeSingle(
                          layer: linear,
                          groupSize: quantizationGroupSize,
                          bits: quantizationBits
                      )
                else { return nil }
                return (path, quantized)
            }
        guard !updates.isEmpty else { return 0 }
        do {
            try module.update(
                modules: ModuleChildren.unflattened(updates),
                verify: .none
            )
            return updates.count
        } catch {
            print("[Laya] quantization skipped a subtree: \(error)")
            return 0
        }
    }

    /// Quantizes the Sequential scorer. It is rebuilt instead of updated
    /// because the first child (LayerNorm) is not quantizable.
    @discardableResult
    private static func quantizeScorer(of model: LayaDecisionModel) -> Int {
        var layers: [UnaryLayer] = []
        var replaced = 0
        for layer in model.scorer.layers {
            if let linear = layer as? Linear,
               linear.weight.dim(-1) % quantizationGroupSize == 0,
               let quantized = quantizeSingle(
                   layer: linear,
                   groupSize: quantizationGroupSize,
                   bits: quantizationBits
               ) as? UnaryLayer {
                layers.append(quantized)
                replaced += 1
            } else {
                layers.append(layer)
            }
        }
        guard replaced > 0 else { return 0 }
        do {
            try model.update(
                modules: ModuleChildren.unflattened([
                    "scorer": Sequential(layers: layers)
                ]),
                verify: .none
            )
            return replaced
        } catch {
            print("[Laya] scorer quantization skipped: \(error)")
            return 0
        }
    }

    func classifyBatch(_ texts: [String], threshold: Float = 0.55) throws -> [LayaClassificationResponse] {
        guard !texts.isEmpty else { return [] }
        try Task.checkCancellation()
        let started = ContinuousClock.now

        let unsafeProbabilities = try unsafeProbabilities(for: texts)
        let unsafeIndices = unsafeProbabilities.indices.filter {
            unsafeProbabilities[$0] >= threshold
        }
        let categories = try categoryLabels(
            for: unsafeIndices.map { texts[$0] }
        )

        let duration = started.duration(to: .now)
        let milliseconds = Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1e15

        var categoryByIndex: [Int: String] = [:]
        for (offset, index) in unsafeIndices.enumerated() {
            categoryByIndex[index] = categories[offset]
        }

        return texts.indices.map { index in
            let probability = unsafeProbabilities[index]
            let safe = probability < threshold
            let category = categoryByIndex[index] ?? "safe"
            let reason = safe ? "Safe content" : Self.reasons[category, default: "Sensitive content"]
            let confidence = max(probability, 1 - probability)
            return LayaClassificationResponse(
                safe: safe,
                reason: reason,
                confidence: Double(confidence),
                latencyMs: milliseconds
            )
        }
    }

    private func unsafeProbabilities(for texts: [String]) throws -> [Float] {
        let items = texts.map { prepare(state: $0, question: Self.unsafeQuestion) }
        let batch = collate(items)
        let logits = model(
            inputIDs: batch.inputIDs,
            attentionMask: batch.attentionMask,
            markerPositions: batch.markerPositions,
            markerMask: batch.markerMask,
            questionTypes: batch.questionTypes
        )
        let unsafeTemperature = temperature(questionType: 2, optionCount: 2)
        let probabilities = softmax(logits[0 ..< texts.count, 0 ..< 2] / unsafeTemperature, axis: -1)
        eval(probabilities)
        try Task.checkCancellation()
        return probabilities[0 ..< texts.count, 1].asArray(Float.self)
    }

    private func categoryLabels(for texts: [String]) throws -> [String] {
        guard !texts.isEmpty else { return [] }
        let items = texts.map { prepare(state: $0, question: Self.categoryQuestion) }
        let batch = collate(items)
        let logits = model(
            inputIDs: batch.inputIDs,
            attentionMask: batch.attentionMask,
            markerPositions: batch.markerPositions,
            markerMask: batch.markerMask,
            questionTypes: batch.questionTypes
        )
        let categoryTemperature = temperature(questionType: 0, optionCount: 8)
        let probabilities = softmax(logits[0 ..< texts.count, 0 ..< 8] / categoryTemperature, axis: -1)
        eval(probabilities)
        try Task.checkCancellation()

        return try (0 ..< texts.count).map { row in
            let index = probabilities[row].argMax().item(Int32.self)
            guard Self.categoryQuestion.options.indices.contains(Int(index)) else {
                throw LayaMLXError.invalidModelOutput
            }
            return Self.categoryQuestion.options[Int(index)].label
        }
    }

    private func prepare(state: String, question: LayaQuestion) -> LayaPreparedItem {
        let cleanInstructions = question.instructions.replacingOccurrences(of: "[MASK]", with: " ")
        var headIDs = tokenizer.encode(
            text: "\(question.kind.rawValue) question: \(cleanInstructions)",
            addSpecialTokens: false
        ).map(Int32.init)

        var optionIDs = question.options.map { option -> [Int32] in
            let text = option.rendered.replacingOccurrences(of: "[MASK]", with: " ")
            let encoded = tokenizer.encode(text: " " + text, addSpecialTokens: false)
            return [maskTokenID] + encoded.prefix(48).map(Int32.init)
        }

        var optionBudget = configuration.headMaxLength - optionIDs.reduce(0) { $0 + $1.count }
        if optionBudget < 16 {
            let perOption = max(4, (configuration.headMaxLength - 16) / max(1, optionIDs.count))
            optionIDs = optionIDs.map { Array($0.prefix(perOption)) }
            optionBudget = configuration.headMaxLength - optionIDs.reduce(0) { $0 + $1.count }
        }
        headIDs = Array(headIDs.prefix(max(8, optionBudget)))

        var ids = [clsTokenID] + headIDs + [separatorTokenID]
        var markers: [Int32] = []
        for option in optionIDs {
            markers.append(Int32(ids.count))
            ids.append(contentsOf: option)
        }
        ids.append(separatorTokenID)

        let room = max(0, configuration.maxLength - ids.count - 1)
        let cleanState = state.replacingOccurrences(of: "[MASK]", with: " ")
        let stateIDs = tokenizer.encode(text: cleanState, addSpecialTokens: false)
        ids.append(contentsOf: stateIDs.prefix(room).map(Int32.init))
        ids.append(separatorTokenID)

        return LayaPreparedItem(
            ids: Array(ids.prefix(configuration.maxLength)),
            markerPositions: markers.filter { $0 < configuration.maxLength },
            questionType: question.kind.index
        )
    }

    private func collate(_ items: [LayaPreparedItem]) -> LayaBatch {
        let batchSize = items.count
        let length = items.map(\.ids.count).max() ?? 0
        let markerCount = max(2, items.map(\.markerPositions.count).max() ?? 0)

        var inputIDs = Array(repeating: paddingTokenID, count: batchSize * length)
        var attentionMask = Array(repeating: false, count: batchSize * length)
        var markerPositions = Array(repeating: Int32(0), count: batchSize * markerCount)
        var markerMask = Array(repeating: false, count: batchSize * markerCount)

        for (row, item) in items.enumerated() {
            for (column, token) in item.ids.enumerated() {
                inputIDs[row * length + column] = token
                attentionMask[row * length + column] = true
            }
            for (column, marker) in item.markerPositions.enumerated() {
                markerPositions[row * markerCount + column] = marker
                markerMask[row * markerCount + column] = true
            }
        }

        return LayaBatch(
            inputIDs: MLXArray(inputIDs).reshaped(batchSize, length),
            attentionMask: MLXArray(attentionMask).reshaped(batchSize, length),
            markerPositions: MLXArray(markerPositions).reshaped(batchSize, markerCount),
            markerMask: MLXArray(markerMask).reshaped(batchSize, markerCount),
            questionTypes: MLXArray(items.map(\.questionType))
        )
    }

    private func temperature(questionType: Int, optionCount: Int) -> Float {
        let kind = ["choice", "score", "noul"][questionType]
        let size = switch optionCount {
        case ...2: "2"
        case 3 ... 5: "3-5"
        case 6 ... 10: "6-10"
        default: "11+"
        }
        return configuration.temperaturesByOptions["\(kind):\(size)"]
            ?? configuration.temperatures[questionType]
    }
}

private struct LayaBatch {
    let inputIDs: MLXArray
    let attentionMask: MLXArray
    let markerPositions: MLXArray
    let markerMask: MLXArray
    let questionTypes: MLXArray
}

private final class LayaEmbeddings: Module {
    @ModuleInfo(key: "tok_embeddings") var tokenEmbeddings: Embedding
    @ModuleInfo var norm: LayerNorm

    init(_ configuration: LayaEncoderConfiguration) {
        _tokenEmbeddings.wrappedValue = Embedding(
            embeddingCount: configuration.vocabSize,
            dimensions: configuration.hiddenSize
        )
        norm = LayerNorm(
            dimensions: configuration.hiddenSize,
            eps: configuration.normEpsilon,
            bias: configuration.normBias
        )
    }

    func callAsFunction(_ ids: MLXArray) -> MLXArray {
        norm(tokenEmbeddings(ids))
    }
}

private final class LayaEncoderAttention: Module {
    @ModuleInfo(key: "Wqkv") var queryKeyValue: Linear
    @ModuleInfo(key: "Wo") var output: Linear

    private let numberOfHeads: Int
    private let headDimension: Int
    private let ropeBase: Float

    init(_ configuration: LayaEncoderConfiguration, attentionType: String) {
        numberOfHeads = configuration.numAttentionHeads
        headDimension = configuration.headDimension
        ropeBase = configuration.ropeBase(for: attentionType)
        _queryKeyValue.wrappedValue = Linear(
            configuration.hiddenSize,
            3 * configuration.hiddenSize,
            bias: configuration.attentionBias
        )
        _output.wrappedValue = Linear(
            configuration.hiddenSize,
            configuration.hiddenSize,
            bias: configuration.attentionBias
        )
    }

    func callAsFunction(_ x: MLXArray, mask: MLXArray) -> MLXArray {
        let batch = x.dim(0)
        let length = x.dim(1)
        let projected = queryKeyValue(x).reshaped(
            batch, length, 3, numberOfHeads, headDimension
        )
        let parts = projected.split(parts: 3, axis: 2)
        var queries = parts[0].squeezed(axis: 2).transposed(0, 2, 1, 3)
        var keys = parts[1].squeezed(axis: 2).transposed(0, 2, 1, 3)
        let values = parts[2].squeezed(axis: 2).transposed(0, 2, 1, 3)
        queries = RoPE(
            queries,
            dimensions: headDimension,
            traditional: false,
            base: ropeBase,
            scale: 1,
            offset: 0
        )
        keys = RoPE(
            keys,
            dimensions: headDimension,
            traditional: false,
            base: ropeBase,
            scale: 1,
            offset: 0
        )
        let attended = scaledDotProductAttention(
            queries: queries,
            keys: keys,
            values: values,
            scale: 1 / sqrt(Float(headDimension)),
            mask: mask
        )
        return output(attended.transposed(0, 2, 1, 3).reshaped(batch, length, -1))
    }
}

private final class LayaEncoderMLP: Module {
    @ModuleInfo(key: "Wi") var input: Linear
    @ModuleInfo(key: "Wo") var output: Linear

    init(_ configuration: LayaEncoderConfiguration) {
        _input.wrappedValue = Linear(
            configuration.hiddenSize,
            2 * configuration.intermediateSize,
            bias: configuration.mlpBias
        )
        _output.wrappedValue = Linear(
            configuration.intermediateSize,
            configuration.hiddenSize,
            bias: configuration.mlpBias
        )
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let (value, gate) = input(x).split(axis: -1)
        return output(gelu(value) * gate)
    }
}

private final class LayaEncoderLayer: Module {
    @ModuleInfo(key: "attn_norm") var attentionNorm: UnaryLayer
    @ModuleInfo(key: "attn") var attention: LayaEncoderAttention
    @ModuleInfo(key: "mlp_norm") var mlpNorm: LayerNorm
    @ModuleInfo var mlp: LayaEncoderMLP

    let attentionType: String

    init(_ configuration: LayaEncoderConfiguration, index: Int) {
        attentionType = configuration.layerTypes[index]
        _attentionNorm.wrappedValue = index == 0
            ? Identity()
            : LayerNorm(
                dimensions: configuration.hiddenSize,
                eps: configuration.normEpsilon,
                bias: configuration.normBias
            )
        _attention.wrappedValue = LayaEncoderAttention(
            configuration,
            attentionType: attentionType
        )
        _mlpNorm.wrappedValue = LayerNorm(
            dimensions: configuration.hiddenSize,
            eps: configuration.normEpsilon,
            bias: configuration.normBias
        )
        mlp = LayaEncoderMLP(configuration)
    }

    func callAsFunction(_ x: MLXArray, mask: MLXArray) -> MLXArray {
        let attended = x + attention(attentionNorm(x), mask: mask)
        return attended + mlp(mlpNorm(attended))
    }
}

private final class LayaModernBERT: Module {
    @ModuleInfo var embeddings: LayaEmbeddings
    @ModuleInfo var layers: [LayaEncoderLayer]
    @ModuleInfo(key: "final_norm") var finalNorm: LayerNorm

    private let localAttention: Int

    init(_ configuration: LayaEncoderConfiguration) {
        embeddings = LayaEmbeddings(configuration)
        layers = (0 ..< configuration.numHiddenLayers).map {
            LayaEncoderLayer(configuration, index: $0)
        }
        _finalNorm.wrappedValue = LayerNorm(
            dimensions: configuration.hiddenSize,
            eps: configuration.normEpsilon,
            bias: configuration.normBias
        )
        localAttention = configuration.localAttention
    }

    func callAsFunction(_ inputIDs: MLXArray, attentionMask: MLXArray) -> MLXArray {
        var x = embeddings(inputIDs)
        let masks = attentionMasks(attentionMask)
        for layer in layers {
            x = layer(x, mask: masks[layer.attentionType]!)
        }
        return finalNorm(x)
    }

    private func attentionMasks(_ attentionMask: MLXArray) -> [String: MLXArray] {
        let valid = attentionMask.asType(.bool)
        let full = valid.expandedDimensions(axes: [1, 2])
        let positions = MLXArray(0 ..< valid.dim(1))
        var local = abs(
            positions.expandedDimensions(axis: 1) - positions.expandedDimensions(axis: 0)
        ) .<= (localAttention / 2)
        local = local.expandedDimensions(axes: [0, 1])
        let paddedQueries = logicalNot(valid.expandedDimensions(axes: [1, 3]))
        local = (local .|| paddedQueries) .&& full
        return ["full_attention": full, "sliding_attention": local]
    }
}

private final class LayaHeadAttention: Module {
    @ModuleInfo(key: "in_proj") var inputProjection: Linear
    @ModuleInfo(key: "out_proj") var outputProjection: Linear

    private let numberOfHeads: Int
    private let headDimension: Int

    init(dimensions: Int) {
        numberOfHeads = max(1, dimensions / 64)
        headDimension = dimensions / numberOfHeads
        _inputProjection.wrappedValue = Linear(dimensions, 3 * dimensions)
        _outputProjection.wrappedValue = Linear(dimensions, dimensions)
    }

    func callAsFunction(_ x: MLXArray, mask: MLXArray) -> MLXArray {
        let batch = x.dim(0)
        let length = x.dim(1)
        let projected = inputProjection(x).reshaped(
            batch, length, 3, numberOfHeads, headDimension
        )
        let parts = projected.split(parts: 3, axis: 2)
        let queries = parts[0].squeezed(axis: 2).transposed(0, 2, 1, 3)
        let keys = parts[1].squeezed(axis: 2).transposed(0, 2, 1, 3)
        let values = parts[2].squeezed(axis: 2).transposed(0, 2, 1, 3)
        let attended = scaledDotProductAttention(
            queries: queries,
            keys: keys,
            values: values,
            scale: 1 / sqrt(Float(headDimension)),
            mask: mask
        )
        return outputProjection(
            attended.transposed(0, 2, 1, 3).reshaped(batch, length, -1)
        )
    }
}

private final class LayaHeadLayer: Module {
    @ModuleInfo(key: "self_attn") var selfAttention: LayaHeadAttention
    @ModuleInfo var norm1: LayerNorm
    @ModuleInfo var norm2: LayerNorm
    @ModuleInfo var linear1: Linear
    @ModuleInfo var linear2: Linear

    init(dimensions: Int) {
        _selfAttention.wrappedValue = LayaHeadAttention(dimensions: dimensions)
        norm1 = LayerNorm(dimensions: dimensions)
        norm2 = LayerNorm(dimensions: dimensions)
        linear1 = Linear(dimensions, 4 * dimensions)
        linear2 = Linear(4 * dimensions, dimensions)
    }

    func callAsFunction(_ x: MLXArray, mask: MLXArray) -> MLXArray {
        let attended = x + selfAttention(norm1(x), mask: mask)
        return attended + linear2(relu(linear1(norm2(attended))))
    }
}

private final class LayaDecisionHead: Module {
    @ModuleInfo var layers: [LayaHeadLayer]

    init(dimensions: Int, count: Int) {
        layers = (0 ..< count).map { _ in LayaHeadLayer(dimensions: dimensions) }
    }

    func callAsFunction(_ x: MLXArray, mask: MLXArray) -> MLXArray {
        layers.reduce(x) { value, layer in layer(value, mask: mask) }
    }
}

private final class LayaDecisionModel: Module {
    @ModuleInfo var encoder: LayaModernBERT
    @ModuleInfo var head: LayaDecisionHead
    @ModuleInfo(key: "type_emb") var typeEmbedding: Embedding
    @ModuleInfo var scorer: Sequential

    init(encoderConfiguration: LayaEncoderConfiguration, headLayerCount: Int) {
        encoder = LayaModernBERT(encoderConfiguration)
        head = LayaDecisionHead(
            dimensions: encoderConfiguration.hiddenSize,
            count: headLayerCount
        )
        _typeEmbedding.wrappedValue = Embedding(
            embeddingCount: 3,
            dimensions: encoderConfiguration.hiddenSize
        )
        scorer = Sequential {
            LayerNorm(dimensions: encoderConfiguration.hiddenSize)
            Linear(encoderConfiguration.hiddenSize, encoderConfiguration.hiddenSize)
            GELU()
            Linear(encoderConfiguration.hiddenSize, 1)
        }
    }

    func callAsFunction(
        inputIDs: MLXArray,
        attentionMask: MLXArray,
        markerPositions: MLXArray,
        markerMask: MLXArray,
        questionTypes: MLXArray
    ) -> MLXArray {
        var hidden = encoder(inputIDs, attentionMask: attentionMask)
        hidden = hidden + typeEmbedding(questionTypes).expandedDimensions(axis: 1)
        hidden = head(hidden, mask: attentionMask.expandedDimensions(axes: [1, 2]))

        let batchIndices = MLXArray(0 ..< hidden.dim(0)).expandedDimensions(axis: 1)
        let markers = hidden[batchIndices, maximum(markerPositions, MLXArray(Int32(0)))]
        var logits = scorer(markers).squeezed(axis: -1).asType(.float32)
        logits = which(markerMask, logits, MLXArray(Float(-10_000)))
        return logits
    }
}

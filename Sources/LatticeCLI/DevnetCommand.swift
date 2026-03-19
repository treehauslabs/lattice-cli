import ArgumentParser
import Foundation
import Lattice
import Acorn
import AcornMemoryWorker
import UInt256
#if canImport(Glibc)
import Glibc
#endif

struct DevnetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "devnet",
        abstract: "Start a local development network"
    )

    @Option(help: "P2P listen port")
    var port: UInt16 = 4001

    @Flag(help: "Enable auto-mining")
    var mining: Bool = false

    @Option(help: "Target block time in milliseconds")
    var blockTime: UInt64 = 1000

    @Option(help: "Storage directory")
    var storagePath: String = "/tmp/lattice-devnet"

    @Option(help: "Max transactions per block")
    var maxTx: UInt64 = 100

    func run() async throws {
        printLogo()
        printHeader("Starting Lattice Devnet")

        let keyPair = CryptoUtils.generateKeyPair()
        let address = CryptoUtils.createAddress(from: keyPair.publicKey)

        printKeyValue("Public Key", String(keyPair.publicKey.prefix(32)) + "...")
        printKeyValue("Address", address)
        printKeyValue("Storage", storagePath)
        printKeyValue("P2P Port", "\(port)")
        printKeyValue("Block Time", "\(blockTime)ms")
        printKeyValue("Mining", mining ? "enabled" : "disabled")

        let fm = FileManager.default
        if !fm.fileExists(atPath: storagePath) {
            try fm.createDirectory(atPath: storagePath, withIntermediateDirectories: true)
        }

        let spec = ChainSpec(
            directory: "Nexus",
            maxNumberOfTransactionsPerBlock: maxTx,
            maxStateGrowth: 100_000,
            premine: 0,
            targetBlockTime: blockTime,
            initialRewardExponent: 10
        )

        let genesisConfig = GenesisConfig.standard(spec: spec)
        let nodeConfig = LatticeNodeConfig(
            publicKey: keyPair.publicKey,
            privateKey: keyPair.privateKey,
            listenPort: port,
            storagePath: URL(filePath: storagePath),
            enableLocalDiscovery: true
        )

        printHeader("Initializing Node")

        let node = try await LatticeNode(config: nodeConfig, genesisConfig: genesisConfig)
        let genesisHash = await node.genesisResult.blockHash

        printKeyValue("Genesis CID", String(genesisHash.prefix(32)) + "...")
        printKeyValue("Reward", "\(spec.initialReward) tokens/block")
        printKeyValue("Halving", "every \(spec.halvingInterval) blocks")

        try await node.start()
        printSuccess("Node started on port \(port)")

        if mining {
            await node.startMining(directory: "Nexus")
            printSuccess("Mining started")
        }

        printHeader("Devnet Running")
        print("  Press Ctrl+C to stop")
        print("")

        let keepAlive = AsyncStream<Void> { continuation in
            let src = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
            signal(SIGINT, SIG_IGN)
            src.setEventHandler {
                continuation.finish()
            }
            src.resume()
        }

        for await _ in keepAlive {}

        print("")
        printWarning("Shutting down...")
        if mining {
            await node.stopMining(directory: "Nexus")
        }
        await node.stop()
        printSuccess("Devnet stopped")
    }
}

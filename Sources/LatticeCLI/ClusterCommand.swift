import ArgumentParser
import Foundation
import Lattice
import UInt256
#if canImport(Glibc)
import Glibc
#endif

struct ClusterCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cluster",
        abstract: "Run a multi-node mining cluster"
    )

    @Option(help: "Number of nodes to spawn")
    var nodes: Int = 3

    @Option(help: "Base P2P port (each node increments by 1)")
    var basePort: UInt16 = 4001

    @Flag(help: "Enable mining on all nodes")
    var mining: Bool = false

    @Option(help: "Target block time in milliseconds")
    var blockTime: UInt64 = 1000

    @Option(help: "Base storage directory")
    var storagePath: String = "/tmp/lattice-cluster"

    @Option(help: "Max transactions per block")
    var maxTx: UInt64 = 100

    @Option(help: "Status update interval in seconds")
    var statusInterval: UInt64 = 5

    func run() async throws {
        printLogo()
        printHeader("Starting Lattice Cluster")

        guard nodes >= 1 && nodes <= 64 else {
            printError("Node count must be between 1 and 64")
            throw ExitCode.failure
        }

        printKeyValue("Nodes", "\(nodes)")
        printKeyValue("Ports", "\(basePort)–\(basePort + UInt16(nodes) - 1)")
        printKeyValue("Storage", storagePath)
        printKeyValue("Block Time", "\(blockTime)ms")
        printKeyValue("Mining", mining ? "all nodes" : "disabled")

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
        let client = MultiNodeClient(
            genesisConfig: genesisConfig,
            baseStoragePath: URL(filePath: storagePath)
        )

        printHeader("Spawning Nodes")

        let ids = try await client.spawnNodes(count: nodes, basePort: basePort)
        for id in ids {
            printSuccess("Created \(id)")
        }

        printHeader("Starting Network")

        for id in ids {
            try await client.startNode(id: id)
            let status = try await client.nodeStatus(id: id)
            printSuccess("\(id) listening on port \(status.port)")
        }

        if mining {
            printHeader("Starting Miners")
            for id in ids {
                try await client.startMining(nodeId: id, directory: "Nexus")
                printSuccess("\(id) mining Nexus")
            }
        }

        printHeader("Cluster Running (\(nodes) nodes)")
        print("  Status updates every \(statusInterval)s. Press Ctrl+C to stop.")
        print("")

        let shutdown = AsyncStream<Void> { continuation in
            let src = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
            signal(SIGINT, SIG_IGN)
            src.setEventHandler {
                continuation.finish()
            }
            src.resume()
        }

        let statusTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(statusInterval))
                if Task.isCancelled { break }
                await printClusterStatus(client: client, ids: ids)
            }
        }

        for await _ in shutdown {}

        statusTask.cancel()

        print("")
        printWarning("Shutting down cluster...")
        await client.stopAll()
        printSuccess("All \(nodes) nodes stopped")
    }

    func printClusterStatus(client: MultiNodeClient, ids: [String]) async {
        let statuses = await client.allNodeStatuses()
        guard !statuses.isEmpty else { return }

        let timestamp = DateFormatter.localizedString(
            from: Date(),
            dateStyle: .none,
            timeStyle: .medium
        )
        print("\(Style.dim)── \(timestamp) ──\(Style.reset)")

        var maxHeight: UInt64 = 0
        for s in statuses {
            if s.chainHeight > maxHeight { maxHeight = s.chainHeight }
        }

        for s in statuses {
            let miningLabel = s.miningDirectories.isEmpty
                ? "\(Style.dim)idle\(Style.reset)"
                : "\(Style.green)mining\(Style.reset)"
            let heightColor = s.chainHeight == maxHeight ? Style.green : Style.yellow
            let tip = String(s.chainTip.prefix(16)) + "..."

            print("  \(Style.bold)\(s.id)\(Style.reset)"
                + "  h=\(heightColor)\(s.chainHeight)\(Style.reset)"
                + "  tip=\(Style.dim)\(tip)\(Style.reset)"
                + "  mempool=\(s.mempoolCount)"
                + "  \(miningLabel)")
        }
        print("")
    }
}

import SwiftUI
import WidgetKit
import AppIntents
import Foundation

struct VaultOption: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Vault"
    static var defaultQuery = VaultQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", image: .init(named: "VaultGraphSymbol", isTemplate: false)) }
    static var available: [VaultOption] {
        let info = Bundle.main.infoDictionary ?? [:]
        let roots = (info["VaultGraphVaultRoots"] as? [String] ?? []).map {
            URL(fileURLWithPath: $0, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        }
        let pinned = info["VaultGraphVaultPaths"] as? [String] ?? []
        var candidates: [String] = []
        if let registryPath = info["VaultGraphRegistryPath"] as? String,
           let data = try? Data(contentsOf: URL(fileURLWithPath: registryPath)),
           let registry = try? JSONDecoder().decode(ObsidianRegistry.self, from: data) {
            candidates += registry.vaults.values.map(\.path)
        }
        // iCloud-Vaults can also be discovered before Obsidian updates its registry.
        for root in roots {
            let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            candidates += children.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true &&
                FileManager.default.fileExists(atPath: $0.appendingPathComponent(".obsidian", isDirectory: true).path)
            }.map(\.path)
        }
        candidates += pinned
        var seen = Set<String>()
        return candidates.compactMap { path in
            let url = URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
            let allowed = pinned.contains(url.path) || roots.contains { url.path.hasPrefix($0.path + "/") }
            var isDirectory: ObjCBool = false
            guard allowed, FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue, seen.insert(url.path).inserted else { return nil }
            return VaultOption(id: url.path, name: url.lastPathComponent)
        }.sorted {
            let firstIsDefault = $0.id == pinned.first
            let secondIsDefault = $1.id == pinned.first
            if firstIsDefault != secondIsDefault { return firstIsDefault }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    private struct ObsidianRegistry: Decodable {
        struct Vault: Decodable { let path: String }
        let vaults: [String: Vault]
    }

}
struct VaultQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [VaultOption] {
        VaultOption.available.filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [VaultOption] { VaultOption.available }
    func defaultResult() async -> VaultOption? { VaultOption.available.first }
}
struct SelectVault: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Vault"
    static var description = IntentDescription("Choose the Obsidian vault to display in this widget.")
    @Parameter(title: "Vault") var vault: VaultOption?
    @Parameter(title: "Use Obsidian graph filter", default: true) var useObsidianFilter: Bool
}
struct Entry: TimelineEntry { let date: Date; let graph: GraphSnapshot; var warning: String? = nil }
struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), graph: .empty) }
    func snapshot(for configuration: SelectVault, in context: Context) async -> Entry { await read(configuration) }
    func timeline(for configuration: SelectVault, in context: Context) async -> Timeline<Entry> {
        let entry = await read(configuration)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
    }
    func read(_ configuration: SelectVault) async -> Entry {
        #if LOCAL_WIDGET
        // A deleted or unavailable selection must not silently display another vault.
        let selected = configuration.vault ?? VaultOption.available.first
        guard let selected, VaultOption.available.contains(where: { $0.id == selected.id }) else {
            return Entry(date: Date(), graph: .empty, warning: "No vault configured.")
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let graph: GraphSnapshot
                var warning: String?
                do {
                    graph = try GraphStore.scan(URL(fileURLWithPath: selected.id, isDirectory: true), useObsidianFilter: configuration.useObsidianFilter)
                    try? GraphStore.save(graph, vaultPath: selected.id, useObsidianFilter: configuration.useObsidianFilter)
                } catch {
                    let cached = GraphStore.load(vaultPath: selected.id, useObsidianFilter: configuration.useObsidianFilter)
                    graph = cached.nodes.isEmpty ? GraphSnapshot(vault: selected.name, nodes: [], edges: []) : cached
                    if configuration.useObsidianFilter {
                        warning = "Obsidian filter unavailable. " + (cached.nodes.isEmpty ? "No saved filtered graph." : "Showing the last saved filtered graph.")
                        if let error = error as? ObsidianGraphFilter.FilterError { warning = error.localizedDescription }
                    } else { warning = "Vault unavailable — showing the last saved graph." }
                }
                continuation.resume(returning: Entry(date: Date(), graph: graph, warning: warning))
            }
        }
        #else
        let graph = GraphStore.load()
        guard configuration.useObsidianFilter else { return Entry(date: Date(), graph: graph) }
        return Entry(date: Date(), graph: .empty, warning: "Obsidian graph filter requires the local widget build.")
        #endif
    }
}
struct WidgetView: View {
    let entry: Entry
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Text(entry.graph.vault).font(.headline).lineLimit(1)
            if entry.graph.nodes.isEmpty {
                Text(entry.warning ?? "No notes in this vault.").font(.caption).foregroundStyle(.secondary).frame(maxHeight:.infinity)
            } else { GraphCanvas(graph:entry.graph, stretchesToFit:true) }
            if let warning = entry.warning, !entry.graph.nodes.isEmpty { Text(warning).font(.caption2).foregroundStyle(.secondary) }
            HStack { Spacer(); Text("\(entry.graph.nodes.count) notes · \(entry.graph.edges.count) connections").font(.caption2).foregroundStyle(.secondary) }
        }
        .containerBackground(for:.widget) { Color(nsColor:.windowBackgroundColor) }
    }
}
@main
struct VaultGraphWidget: Widget {
    let kind = "VaultGraph"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind:kind,intent:SelectVault.self,provider:Provider()) { WidgetView(entry:$0) }
            .configurationDisplayName("Vault Graph")
            .description("See how the notes in your Obsidian vault connect.")
            .supportedFamilies([.systemSmall,.systemMedium,.systemLarge])
    }
}

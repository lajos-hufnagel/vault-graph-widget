import Foundation
import CryptoKit
import SwiftUI

struct GraphNode: Codable, Identifiable {
    var id: String
    var name: String
    var category: String
    var x: Double
    var y: Double
    var kind: String? = nil
    var tags: [String]? = nil
    var rgb: UInt32? = nil
    var alpha: Double? = nil
}
struct GraphEdge: Codable { var a: Int; var b: Int; var directed: Bool? = nil; var reverse: Bool? = nil }
struct GraphSnapshot: Codable {
    var vault: String
    var nodes: [GraphNode]
    var edges: [GraphEdge]
    var settings: ObsidianGraphFilter? = nil
    static let empty = GraphSnapshot(vault: "Vault auswählen", nodes: [], edges: [])
}
// The saved graph search is intentionally limited to literal path/file exclusions.
// Reject other syntax rather than silently displaying a different selection.
struct ObsidianGraphFilter: Codable {
    var search: String?
    var showOrphans: Bool?
    var showTags: Bool?
    var showAttachments: Bool?
    var hideUnresolved: Bool?
    var showArrow: Bool?
    var textFadeMultiplier: Double?
    var nodeSizeMultiplier: Double?
    var lineSizeMultiplier: Double?
    var centerStrength: Double?
    var repelStrength: Double?
    var linkStrength: Double?
    var linkDistance: Double?
    var scale: Double?
    struct ColorGroup: Codable {
        var query: String
        struct RGBA: Codable { var a: Double; var rgb: UInt32 }
        var color: RGBA
    }
    var colorGroups: [ColorGroup]?
    func colorMatches(_ query: String, _ node: GraphNode) throws -> Bool {
        if query.isEmpty { return true }
        let fields = ["path:": node.id, "file:": node.name]
        for (prefix, value) in fields where query.hasPrefix(prefix) {
            var term = String(query.dropFirst(prefix.count))
            if term.hasPrefix("\"") && term.hasSuffix("\"") { term = String(term.dropFirst().dropLast()) }
            if term.hasPrefix("/") && term.hasSuffix("/") {
                let expression = try NSRegularExpression(pattern: String(term.dropFirst().dropLast()))
                return expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
            }
            return value.range(of: term, options: .caseInsensitive) != nil
        }
        if query.hasPrefix("tag:") {
            let term = String(query.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: "\"#"))
            return (node.tags ?? []).contains { $0 == term || $0.hasPrefix(term + "/") }
        }
        throw FilterError.unsupportedColors
    }
    func colored(_ node: GraphNode) throws -> GraphNode {
        var result = node
        for group in colorGroups ?? [] where try colorMatches(group.query, node) {
            result.rgb = group.color.rgb; result.alpha = group.color.a; break
        }
        return result
    }
    struct Exclusion { let field: String; let value: String }
    enum FilterError: LocalizedError {
        case unsupportedSearch, unsupportedColors
        var errorDescription: String? { self == .unsupportedSearch ? "Unsupported Obsidian search. Only -path: and -file: exclusions are supported." : "Unsupported Obsidian color query. Supported: path:, file: (including regex), tag:." }
    }
    func exclusions() throws -> [Exclusion] {
        let query = (search ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let expression = try NSRegularExpression(pattern: #"-(path|file):(?:"([^"\\]*)"|([^\s"()]+))"#)
        var cursor = query.startIndex
        var result: [Exclusion] = []
        for match in expression.matches(in: query, range: NSRange(query.startIndex..., in: query)) {
            guard let range = Range(match.range, in: query),
                  query[cursor..<range.lowerBound].allSatisfy({ $0.isWhitespace }),
                  range.lowerBound == query.startIndex || query[query.index(before: range.lowerBound)].isWhitespace,
                  range.upperBound == query.endIndex || query[range.upperBound].isWhitespace,
                  let field = Range(match.range(at: 1), in: query),
                  let value = Range(match.range(at: match.range(at: 2).location == NSNotFound ? 3 : 2), in: query)
            else { throw FilterError.unsupportedSearch }
            let literal = String(query[value])
            guard !literal.isEmpty, !literal.hasPrefix("/") else { throw FilterError.unsupportedSearch }
            result.append(Exclusion(field: String(query[field]), value: literal))
            cursor = range.upperBound
        }
        guard query[cursor...].allSatisfy({ $0.isWhitespace }) else { throw FilterError.unsupportedSearch }
        return result
    }
    func apply(to graph: GraphSnapshot) throws -> GraphSnapshot {
        let rules = try exclusions()
        var indices = graph.nodes.indices.filter { i in
            let node = graph.nodes[i]
            return !rules.contains { rule in
                let text = rule.field == "path" ? node.id : node.name
                return text.range(of: rule.value, options: .caseInsensitive) != nil
            }
        }
        let visible = Set(indices)
        let edges = graph.edges.filter { visible.contains($0.a) && visible.contains($0.b) }
        let linked = Set(edges.flatMap { [$0.a, $0.b] })
        // Tags and unresolved links exist only through a visible source note.
        // Orphan visibility applies to actual files, not leftover virtual nodes.
        indices.removeAll {
            let virtual = graph.nodes[$0].kind == "tag" || graph.nodes[$0].kind == "unresolved"
            return !linked.contains($0) && (virtual || showOrphans == false)
        }
        let mapping = Dictionary(uniqueKeysWithValues: indices.enumerated().map { ($0.element, $0.offset) })
        let remapped = edges.compactMap { edge -> GraphEdge? in
            guard let a = mapping[edge.a], let b = mapping[edge.b] else { return nil }
            return GraphEdge(a: a, b: b, directed: edge.directed, reverse: edge.reverse)
        }
        let nodes = GraphStore.positioned(indices.map { graph.nodes[$0] }, remapped, settings: self)
        return GraphSnapshot(vault: graph.vault, nodes: nodes, edges: remapped, settings: self)
    }
}
enum GraphStore {
    static let group = "group.de.lajoshufnagel.VaultGraph"
    static var url: URL? {
        #if LOCAL_WIDGET
        let folder = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        return folder.appendingPathComponent("graph.json")
        #else
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("graph.json")
        #endif
    }
    static func cacheURL(vaultPath: String?, useObsidianFilter: Bool = false) -> URL? {
        guard let url, let vaultPath else { return url }
        let key = SHA256.hash(data: Data((vaultPath + (useObsidianFilter ? "\nobsidian-filter" : "")).utf8)).map { String(format: "%02x", $0) }.joined()
        return url.deletingLastPathComponent().appendingPathComponent("graph-\(key).json")
    }
    static func load(vaultPath: String? = nil, useObsidianFilter: Bool = false) -> GraphSnapshot {
        guard let url = cacheURL(vaultPath: vaultPath, useObsidianFilter: useObsidianFilter), let data = try? Data(contentsOf: url), let graph = try? JSONDecoder().decode(GraphSnapshot.self, from: data) else { return .empty }
        return graph
    }
    static func save(_ graph: GraphSnapshot, vaultPath: String? = nil, useObsidianFilter: Bool = false) throws {
        guard let url = cacheURL(vaultPath: vaultPath, useObsidianFilter: useObsidianFilter) else { throw CocoaError(.fileNoSuchFile) }
        try JSONEncoder().encode(graph).write(to: url, options: .atomic)
    }
    static func scan(_ vault: URL, useObsidianFilter: Bool = false) throws -> GraphSnapshot {
        let vault = vault.resolvingSymlinksInPath().standardizedFileURL
        let configURL = vault.appendingPathComponent(".obsidian/graph.json")
        var settings = try JSONDecoder().decode(ObsidianGraphFilter.self, from: Data(contentsOf: configURL))
        if !useObsidianFilter {
            // Obsidian's default FILTER options; colors/display/forces still come
            // from the selected vault. Never mutate graph.json itself.
            settings.search = ""
            settings.showTags = false
            settings.showAttachments = false
            settings.hideUnresolved = false
            settings.showOrphans = true
        }
        _ = try settings.exclusions()
        let fm = FileManager.default
        guard let iterator = fm.enumerator(at: vault, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]), fm.isReadableFile(atPath: vault.path) else { throw CocoaError(.fileReadNoPermission) }
        let files = iterator.compactMap { $0 as? URL }.map {
            $0.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.appendingPathComponent($0.lastPathComponent)
        }.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.path < $1.path }
        let prefix = vault.path + "/"
        let markdown = files.filter { $0.pathExtension.lowercased() == "md" }
        let paths = files.map { String($0.path.dropFirst(prefix.count)) }
        let allPaths = Set(paths)
        let basenames = Dictionary(grouping: paths, by: { ($0 as NSString).lastPathComponent })
        var nodes: [GraphNode] = []
        var index: [String: Int] = [:]
        func add(_ id: String, _ kind: String, tags: [String] = []) -> Int {
            if let existing = index[id] { return existing }
            let i = nodes.count; index[id] = i
            nodes.append(GraphNode(id: id, name: kind == "tag" ? id : (id as NSString).deletingPathExtension.components(separatedBy: "/").last!, category: id.components(separatedBy: "/").first!, x: 0, y: 0, kind: kind, tags: tags))
            return i
        }
        for file in markdown { _ = add(String(file.path.dropFirst(prefix.count)), "note") }
        if settings.showAttachments == true {
            for file in files where file.pathExtension.lowercased() != "md" { _ = add(String(file.path.dropFirst(prefix.count)), "attachment") }
        }
        let wiki = try NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#)
        let markdownLinks = try NSRegularExpression(pattern: #"!?\[[^\]]*\]\(([^\s)]+)(?:\s+"[^"]*")?\)"#)
        let fences = try NSRegularExpression(pattern: #"```[\s\S]*?```|~~~[\s\S]*?~~~|`[^`\n]*`"#)
        let inlineTags = try NSRegularExpression(pattern: #"(?:^|\s)#([\p{L}\p{N}_/-]+)"#)
        var edges: [GraphEdge] = []; var seen: [String: Int] = [:]
        func link(_ a: Int, _ b: Int, directed: Bool = true) {
            guard a != b else { return }
            let key = "\(min(a,b)):\(max(a,b))"
            if let existing = seen[key] {
                if edges[existing].a != a && directed { edges[existing].reverse = true }
            } else {
                seen[key] = edges.count
                edges.append(GraphEdge(a:a,b:b,directed:directed))
            }
        }
        func resolve(_ target: String, _ src: String) -> String? {
            let parent = (src as NSString).deletingLastPathComponent
            let relative = URL(fileURLWithPath: parent, relativeTo: vault).appendingPathComponent(target).standardizedFileURL.path
            let rel = relative.hasPrefix(prefix) ? String(relative.dropFirst(prefix.count)) : ""
            for candidate in [target, target + ".md", rel, rel + ".md"] where allPaths.contains(candidate) { return candidate }
            for name in [(target as NSString).lastPathComponent, (target as NSString).lastPathComponent + ".md"] {
                if let matches = basenames[name], matches.count == 1 { return matches[0] }
            }
            return nil
        }
        for file in markdown {
            let src = String(file.path.dropFirst(prefix.count)); let a = index[src]!
            let raw = try String(contentsOf: file, encoding: .utf8)
            var tags: [String] = []
            var body = raw
            if raw.hasPrefix("---\n"), let end = raw.range(of: "\n---", range: raw.index(raw.startIndex, offsetBy: 4)..<raw.endIndex) {
                let yaml = String(raw[raw.index(raw.startIndex, offsetBy: 4)..<end.lowerBound])
                var inTags = false
                for line in yaml.components(separatedBy: "\n") {
                    if line.hasPrefix("tags:") {
                        inTags = true
                        let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if !value.isEmpty { tags += value.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).components(separatedBy: ",") }
                    } else if inTags && line.trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                        tags.append(String(line.trimmingCharacters(in: .whitespaces).dropFirst(2)))
                    } else if !line.trimmingCharacters(in: .whitespaces).isEmpty { inTags = false }
                }
                body = String(raw[end.upperBound...])
            }
            body = fences.stringByReplacingMatches(in: body, range: NSRange(body.startIndex..., in: body), withTemplate: "")
            for m in inlineTags.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                if let r = Range(m.range(at: 1), in: body) { tags.append(String(body[r])) }
            }
            tags = Array(Set(tags.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'#")) }.filter { !$0.isEmpty })).sorted()
            nodes[a].tags = tags
            if settings.showTags == true { for tag in tags { link(a, add("#" + tag, "tag"), directed: false) } }
            var targets: [String] = []
            for expression in [wiki, markdownLinks] {
                for m in expression.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                    if let r = Range(m.range(at: 1), in: body) { targets.append(String(body[r])) }
                }
            }
            for original in targets {
                let target = (original.removingPercentEncoding ?? original).components(separatedBy: "|")[0].components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
                if target.isEmpty || target.contains("://") || target.hasPrefix("mailto:") || target.hasPrefix("data:") { continue }
                if let dest = resolve(target, src) {
                    if let b = index[dest] { link(a, b) }
                } else if settings.hideUnresolved != true {
                    let ext = (target as NSString).pathExtension.lowercased()
                    if !ext.isEmpty && ext != "md" && settings.showAttachments != true { continue }
                    link(a, add(target, "unresolved"))
                }
            }
        }
        nodes = try nodes.map { try settings.colored($0) }
        let graph = GraphSnapshot(vault: vault.lastPathComponent, nodes: nodes, edges: edges, settings: settings)
        return try settings.apply(to: graph)
    }
    static func positioned(_ input:[GraphNode], _ edges:[GraphEdge], settings: ObsidianGraphFilter? = nil) -> [GraphNode] {
        guard !input.isEmpty else { return [] }
        var degree = Array(repeating: 0, count: input.count)
        for edge in edges { degree[edge.a] += 1; degree[edge.b] += 1 }
        let linked = input.indices.filter { degree[$0] > 0 }
        let isolated = input.indices.filter { degree[$0] == 0 }
        var positions = input.indices.map { i -> CGPoint in
            let angle = Double(i) * 2.399963, radius = 45 + sqrt(Double(i)) * 24
            return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        }
        for step in 0..<320 {
            var delta = Array(repeating: CGPoint.zero, count: positions.count)
            for (index, i) in linked.enumerated() {
                for j in linked.dropFirst(index + 1) {
                    let dx = positions[i].x - positions[j].x, dy = positions[i].y - positions[j].y
                    let force = 900 * max(0, settings?.repelStrength ?? 10) / 10 / max(25, dx * dx + dy * dy)
                    delta[i].x += dx * force; delta[i].y += dy * force
                    delta[j].x -= dx * force; delta[j].y -= dy * force
                }
            }
            for edge in edges {
                let dx = positions[edge.b].x - positions[edge.a].x
                let dy = positions[edge.b].y - positions[edge.a].y
                let distance = max(1, hypot(dx, dy))
                // Hubs must not pull all their neighbours into the same small area.
                let hubWeight = sqrt(Double(max(degree[edge.a], degree[edge.b])))
                let force = (distance - max(1, settings?.linkDistance ?? 250) * 95 / 250) * 0.045 * max(0, settings?.linkStrength ?? 1) / hubWeight
                delta[edge.a].x += dx / distance * force; delta[edge.a].y += dy / distance * force
                delta[edge.b].x -= dx / distance * force; delta[edge.b].y -= dy / distance * force
            }
            let cooling = 0.9 * (1 - Double(step) / 360)
            for i in linked {
                let dx = (delta[i].x - positions[i].x * 0.001 * max(0, settings?.centerStrength ?? 0.52) / 0.52) * cooling
                let dy = (delta[i].y - positions[i].y * 0.001 * max(0, settings?.centerStrength ?? 0.52) / 0.52) * cooling
                let limit = max(1, hypot(dx, dy) / 8)
                positions[i].x += dx / limit; positions[i].y += dy / limit
            }
        }
        let spanX = (linked.map { positions[$0].x }.max() ?? 0) - (linked.map { positions[$0].x }.min() ?? 0)
        let spanY = (linked.map { positions[$0].y }.max() ?? 0) - (linked.map { positions[$0].y }.min() ?? 0)
        let minimumDistance = max(40, max(spanX, spanY) / max(12, sqrt(Double(linked.count)) * 1.6))
        // A direct collision pass also separates close neighbours around hubs.
        for _ in 0..<80 {
            for (index, i) in linked.enumerated() {
                for j in linked.dropFirst(index + 1) {
                    var dx = positions[j].x - positions[i].x, dy = positions[j].y - positions[i].y
                    var distance = hypot(dx, dy)
                    if distance < 0.001 { dx = 1; dy = 0; distance = 1 }
                    guard distance < minimumDistance else { continue }
                    let correction = (minimumDistance - distance) / 2
                    positions[i].x -= dx / distance * correction; positions[i].y -= dy / distance * correction
                    positions[j].x += dx / distance * correction; positions[j].y += dy / distance * correction
                }
            }
        }
        // Keep unlinked notes in a compact row/grid instead of allowing outliers
        // to shrink the linked graph when fitting the widget.
        if !isolated.isEmpty {
            let minX = linked.map { positions[$0].x }.min() ?? 0
            let maxX = linked.map { positions[$0].x }.max() ?? 0
            let maxY = linked.map { positions[$0].y }.max() ?? -60
            let columns = linked.isEmpty ? max(1, Int(ceil(sqrt(Double(isolated.count)))))
                : max(1, min(isolated.count, Int(max(minimumDistance, maxX - minX) / minimumDistance) + 1))
            let centerX = (minX + maxX) / 2
            let spacing = linked.isEmpty ? 55 : max(minimumDistance, (maxX - minX) / Double(max(1, columns - 1)))
            for (index, i) in isolated.enumerated() {
                let row = index / columns, column = index % columns
                let rowCount = min(columns, isolated.count - row * columns)
                positions[i] = CGPoint(x: centerX + (Double(column) - Double(rowCount - 1) / 2) * spacing,
                                       y: maxY + (linked.isEmpty ? 60 : minimumDistance * 1.4) + Double(row) * spacing)
            }
        }
        return input.enumerated().map { i, node in var n = node; n.x = positions[i].x; n.y = positions[i].y; return n }
    }
}
func nodeColor(_ node: GraphNode) -> Color {
    guard let hex = node.rgb else { return .secondary }
    return Color(red: Double((hex >> 16)&255)/255, green: Double((hex >> 8)&255)/255, blue: Double(hex&255)/255).opacity(node.alpha ?? 1)
}
struct GraphCanvas: View {
    let graph: GraphSnapshot
    var zoom: CGFloat = 1
    var offset: CGSize = .zero
    var selected: String? = nil
    var onSelect: ((String?) -> Void)? = nil
    var stretchesToFit: Bool = false
    // A desktop widget fits its own bounds; Obsidian's window zoom must not
    // shrink (or clip) the already fitted graph in either filter mode.
    var viewportZoom: CGFloat { stretchesToFit ? 1 : max(0.01, graph.settings?.scale ?? 1) }
    func position(_ n: GraphNode, _ size: CGSize) -> CGPoint {
        let minX = graph.nodes.map(\.x).min() ?? 0
        let maxX = graph.nodes.map(\.x).max() ?? 0
        let minY = graph.nodes.map(\.y).min() ?? 0
        let maxY = graph.nodes.map(\.y).max() ?? 0
        let width = max(1, maxX - minX), height = max(1, maxY - minY)
        let padding: CGFloat = 12
        let fitX = max(1, size.width - padding * 2) / width
        let fitY = max(1, size.height - padding * 2) / height
        let scaleX = stretchesToFit ? fitX : min(fitX, fitY)
        let scaleY = stretchesToFit ? fitY : min(fitX, fitY)
        return CGPoint(x: size.width / 2 + offset.width + (n.x - (minX + maxX) / 2) * scaleX * zoom * viewportZoom,
                       y: size.height / 2 + offset.height + (n.y - (minY + maxY) / 2) * scaleY * zoom * viewportZoom)
    }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                for e in graph.edges {
                    var path = Path(); path.move(to: position(graph.nodes[e.a], size)); path.addLine(to: position(graph.nodes[e.b], size))
                    context.stroke(path, with: .color(.secondary.opacity(0.65)), lineWidth: 0.45 * max(0, graph.settings?.lineSizeMultiplier ?? 1))
                    if graph.settings?.showArrow == true && e.directed == true {
                        let a = position(graph.nodes[e.a], size), b = position(graph.nodes[e.b], size)
                        let angle = atan2(b.y-a.y,b.x-a.x), tip = CGPoint(x:b.x-cos(angle)*5,y:b.y-sin(angle)*5)
                        var arrow = Path(); arrow.move(to: CGPoint(x:tip.x-cos(angle-0.5)*5,y:tip.y-sin(angle-0.5)*5)); arrow.addLine(to:tip); arrow.addLine(to:CGPoint(x:tip.x-cos(angle+0.5)*5,y:tip.y-sin(angle+0.5)*5))
                        context.stroke(arrow,with:.color(.secondary),lineWidth:max(0,graph.settings?.lineSizeMultiplier ?? 1))
                        if e.reverse == true {
                            let reverseTip = CGPoint(x:a.x+cos(angle)*5,y:a.y+sin(angle)*5)
                            var back = Path(); back.move(to:CGPoint(x:reverseTip.x+cos(angle-0.5)*5,y:reverseTip.y+sin(angle-0.5)*5)); back.addLine(to:reverseTip); back.addLine(to:CGPoint(x:reverseTip.x+cos(angle+0.5)*5,y:reverseTip.y+sin(angle+0.5)*5))
                            context.stroke(back,with:.color(.secondary),lineWidth:max(0,graph.settings?.lineSizeMultiplier ?? 1))
                        }
                    }
                }
                for node in graph.nodes {
                    let p = position(node, size)
                    let r: CGFloat = (node.id == selected ? 5 : (min(size.width, size.height) < 150 ? 2.5 : 3.25)) * max(0, graph.settings?.nodeSizeMultiplier ?? 1)
                    context.fill(Path(ellipseIn: CGRect(x: p.x-r, y: p.y-r, width: r*2, height: r*2)), with: .color(nodeColor(node)))
                }
                // Same fade curve as Obsidian's renderer: clamp(log2(scale)
                // + 1 - textFadeMultiplier, 0, 1). Selection stays readable.
                let effectiveZoom = zoom * max(0.01, graph.settings?.scale ?? 1)
                let textAlpha = min(1, max(0, log2(effectiveZoom) + 1 - (graph.settings?.textFadeMultiplier ?? 0)))
                if textAlpha > 0 {
                    for node in graph.nodes where node.id != selected {
                        let p = position(node, size)
                        context.draw(Text(node.name).font(.system(size: 9)).foregroundStyle(.primary.opacity(textAlpha)), at: CGPoint(x:p.x,y:p.y+10), anchor:.top)
                    }
                }
                if let n = graph.nodes.first(where: { $0.id == selected }) {
                    let p = position(n, size)
                    let text = context.resolve(Text(n.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary))
                    let measured = text.measure(in: CGSize(width: max(1,size.width-24), height: 80))
                    let width = min(size.width-8, measured.width+14), height = measured.height+10
                    let x = min(max(4,p.x-width/2),size.width-width-4), y = min(max(4,p.y+13),size.height-height-4)
                    context.fill(Path(roundedRect: CGRect(x:x,y:y,width:width,height:height),cornerRadius:5),with:.color(Color(nsColor:.windowBackgroundColor)))
                    context.draw(text,in:CGRect(x:x+7,y:y+5,width:width-14,height:height-10))
                }
            }
            .onTapGesture { point in
                let closest = graph.nodes.min { hypot(position($0, geometry.size).x-point.x,position($0, geometry.size).y-point.y) < hypot(position($1, geometry.size).x-point.x,position($1, geometry.size).y-point.y) }
                let hit = closest.flatMap { n -> String? in let p = position(n, geometry.size); return hypot(p.x-point.x,p.y-point.y)<18 ? n.id : nil }
                onSelect?(hit)
            }
        }
        .accessibilityLabel("Graph: \(graph.nodes.count) notes and \(graph.edges.count) connections")
    }
}

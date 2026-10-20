#if LOCAL_WIDGET
import AppKit
import WidgetKit
// WidgetKit braucht ein installiertes App-Bundle, aber keinen laufenden Host.
@main
final class WidgetHost: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = WidgetHost()
        app.delegate = delegate
        app.setActivationPolicy(.prohibited)
        app.run()
        withExtendedLifetime(delegate) {}
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        WidgetCenter.shared.reloadAllTimelines()
        // Keep the registered host alive briefly so the request reaches WidgetKit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSApplication.shared.terminate(nil)
        }
    }
}
#else
import SwiftUI
import Combine
import UniformTypeIdentifiers
import WidgetKit

@main
struct VaultGraphApp: App {
    var body: some Scene { WindowGroup("Vault Graph") { GraphWindow() }.defaultSize(width:700,height:520) }
}
struct GraphWindow: View {
    @State private var graph = GraphSnapshot.empty
    @State private var vault: URL?
    @State private var importer = false
    @State private var message: String?
    @State private var selected: String?
    @State private var zoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var baseOffset = CGSize.zero
    @State private var busy = false
    @State private var signature: String = ""
    private let timer = Timer.publish(every:2,on:.main,in:.common).autoconnect()
    var body: some View {
        VStack(spacing:0) {
            GeometryReader { geometry in
                ZStack(alignment:.bottomTrailing) {
                    GraphCanvas(graph:graph,zoom:zoom,offset:offset,selected:selected,onSelect:{ selected = $0 })
                        .gesture(DragGesture(minimumDistance:4).onChanged { offset = CGSize(width:baseOffset.width+$0.translation.width,height:baseOffset.height+$0.translation.height) }.onEnded { _ in baseOffset = offset })
                    if outside(geometry.size) {
                        Button("Gesamten Graph zeigen") { zoom = 1; offset = .zero; baseOffset = .zero }.buttonStyle(.bordered).padding(12)
                    }
                }
            }
            Divider()
            HStack {
                if let message { Text(message).foregroundStyle(.secondary).lineLimit(2) }
                Spacer()
                Text(selected.map { id in "\(graph.edges.filter { graph.nodes[$0.a].id == id || graph.nodes[$0.b].id == id }.count) Verbindungen" } ?? "\(graph.nodes.count) Notizen · \(graph.edges.count) Verbindungen").font(.caption).foregroundStyle(.secondary)
            }.padding(12)
        }
        .toolbar {
            ToolbarItem(placement:.navigation) { Button(graph.vault) { importer = true } }
            ToolbarItem { Slider(value:$zoom,in:0.5...5).frame(width:100).help("Zoom") }
        }
        .fileImporter(isPresented:$importer,allowedContentTypes:[.folder]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                guard access else { throw CocoaError(.fileReadNoPermission) }
                vault?.stopAccessingSecurityScopedResource(); vault = url; signature = ""
                let bookmark = try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil)
                UserDefaults.standard.set(bookmark,forKey:"vaultBookmark")
                reload()
            } catch { message = error.localizedDescription }
        }
        .onAppear {
            if let data = UserDefaults.standard.data(forKey:"vaultBookmark") {
                var stale = false
                if let url = try? URL(resolvingBookmarkData:data,options:.withSecurityScope,relativeTo:nil,bookmarkDataIsStale:&stale),url.startAccessingSecurityScopedResource() { vault = url; reload() }
            }
        }
        .onReceive(timer) { _ in reload() }
    }
    func outside(_ size: CGSize) -> Bool {
        guard !graph.nodes.isEmpty else { return false }
        let canvas = GraphCanvas(graph:graph,zoom:zoom,offset:offset)
        return graph.nodes.filter { let p = canvas.position($0,size); return p.x<0 || p.y<0 || p.x>size.width || p.y>size.height }.count > graph.nodes.count/2
    }
    func reload() {
        guard let vault, !busy else { return }
        busy = true
        let previousSignature = signature
        // Dateiscan und Layout im Hintergrund; UI und Auswahl bleiben erhalten.
        DispatchQueue.global(qos:.utility).async {
            do {
                let iterator = FileManager.default.enumerator(at:vault,includingPropertiesForKeys:[.contentModificationDateKey,.fileSizeKey],options:[.skipsHiddenFiles])
                let files = iterator?.compactMap { $0 as? URL }.filter { $0.pathExtension == "md" } ?? []
                let current = try files.sorted { $0.path<$1.path }.map { u in let v = try u.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey]); return "\(u.path):\(v.contentModificationDate?.timeIntervalSince1970 ?? 0):\(v.fileSize ?? 0)" }.joined(separator:"\n")
                if current == previousSignature { DispatchQueue.main.async { busy = false }; return }
                let next = try GraphStore.scan(vault)
                var warning: String? = nil
                do { try GraphStore.save(next); WidgetCenter.shared.reloadAllTimelines() }
                catch { warning = "Widget-Freigabe benötigt signierte App mit App Group." }
                DispatchQueue.main.async { graph = next; signature = current; if !next.nodes.contains(where:{$0.id == selected}) { selected = nil }; message = warning; busy = false }
            } catch { DispatchQueue.main.async { message = error.localizedDescription; busy = false } }
        }
    }
}

#endif

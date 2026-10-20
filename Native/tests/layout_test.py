from pathlib import Path
import subprocess, tempfile, sys
source = (Path(__file__).resolve().parents[1] / "Graph.swift").read_text()
source += r"""
try MainActor.assumeIsolated {
    let vault = URL(fileURLWithPath: CommandLine.arguments[1])
    for filtered in [false, true] {
        var graph = try GraphStore.scan(vault, useObsidianFilter: filtered)
        for savedZoom in [0.1, 0.406, 1.0, 4.0] {
            graph.settings?.scale = savedZoom
            for size in [CGSize(width: 160, height: 120), CGSize(width: 350, height: 270), CGSize(width: 700, height: 300)] {
                let canvas = GraphCanvas(graph: graph, stretchesToFit: true)
                let points = graph.nodes.map { canvas.position($0, size) }
                let xs = points.map(\.x), ys = points.map(\.y)
                assert(abs(xs.min()! - 12) < 0.001 && abs(xs.max()! - (size.width - 12)) < 0.001)
                assert(abs(ys.min()! - 12) < 0.001 && abs(ys.max()! - (size.height - 12)) < 0.001)
                assert(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
            }
        }
    }
    print("PASS: both real filter modes fill all three viewport sizes at four saved zoom levels, with safe margins")
}
"""
with tempfile.TemporaryDirectory(prefix="vaultgraph-layout-") as directory:
    script = Path(directory) / "layout.swift"
    script.write_text(source)
    subprocess.run(["swift", "-module-cache-path", "/private/tmp/vaultgraph-swift-cache", str(script), sys.argv[1]], check=True)

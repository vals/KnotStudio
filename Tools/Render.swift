import AppKit
import Foundation
import SceneKit

/// Offscreen renderer for checking the model without opening the app.
///
///   knot-render <out.png> <notation> [key=value ...]
///
/// Keys: steps (show only the first N steps), view (knot|portrait|side|back),
/// tight (0…1), spread, display (fabric|grid|faces), pattern, size, animate
/// (seconds of live stepping instead of an instant settle; `from` sets the
/// notation it starts from), cloth (finesilk|silktwill|wool), collar=off.
@main
struct Render {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 2 else { print("usage: knot-render out.png notation [key=value ...]"); exit(2) }
        var options: [String: String] = [:]
        for arg in args.dropFirst(2) {
            let parts = arg.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { options[parts[0]] = parts[1] }
        }
        let parsed = KnotProgram.parse(args[1])
        if let issue = parsed.issue { FileHandle.standardError.write("note: \(issue)\n".data(using: .utf8)!) }
        var program = parsed.program
        if let steps = options["steps"].flatMap({ Int($0) }) { program = program.prefix(steps) }

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let controller = KnotSceneController()
        var params = KnotParams()
        if let tight = options["tight"].flatMap({ Double($0) }) { params.tightness = tight }
        if let spread = options["spread"].flatMap({ Double($0) }) { params.layerSpread = spread }
        controller.set(params: params)
        var fabric = FabricSettings()
        if let display = options["display"] { fabric.display = FabricDisplay.allCases.first { $0.rawValue.lowercased() == display } ?? .fabric }
        if let pattern = options["pattern"] { fabric.pattern = FabricPattern.allCases.first { $0.rawValue.lowercased().hasPrefix(pattern) } ?? .stripes }
        if let angle = options["angle"].flatMap({ Double($0) }) { fabric.angle = angle }
        if let cloth = options["cloth"] { fabric.cloth = ClothKind.allCases.first { $0.rawValue.lowercased().replacingOccurrences(of: " ", with: "").hasPrefix(cloth) } ?? .twill }
        params.weight = fabric.cloth.weight
        controller.set(params: params)
        if options["collar"] == "off" { controller.showCollar = false }
        controller.apply(fabric: fabric)

        if let seconds = options["animate"].flatMap({ Double($0) }) {
            controller.set(goal: KnotProgram(options["from"] ?? ""))
            controller.settle()
            controller.set(goal: program)
            var time = 0.0
            while time < seconds { controller.advance(1.0 / 60); time += 1.0 / 60 }
        } else {
            controller.set(goal: program)
            controller.settle()
        }
        let view = CameraPreset.allCases.first { $0.rawValue.lowercased() == (options["view"] ?? "knot") } ?? .knot
        controller.place(view)
        if let zoom = options["zoom"].flatMap({ Double($0) }) { controller.cameraNode.camera?.orthographicScale = zoom }
        let side = options["size"].flatMap { Double($0) } ?? 1000
        let image = controller.snapshot(size: NSSize(width: side, height: side))
        guard let png = KnotSceneController.png(image) else { print("could not encode"); exit(1) }
        try png.write(to: URL(fileURLWithPath: args[0]))
        print("\(program.notation.isEmpty ? "(untied)" : program.notation) → \(args[0])  rows \(controller.sim.mesh.rowCount)  triangles \(controller.sim.mesh.triangleCount)  free end \(String(format: "%.1f", controller.sim.freeLength)) cm")
    }
}

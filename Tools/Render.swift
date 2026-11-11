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
/// notation it starts from), cloth (finesilk|silktwill|wool), collar=off, lift
/// (raise the camera, cm), and record=<seconds> to write a frame sequence
/// (see below; Scripts/gifs.sh turns those into GIFs).
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

        let view = CameraPreset.allCases.first { $0.rawValue.lowercased() == (options["view"] ?? "knot") } ?? .knot
        let side = options["size"].flatMap { Double($0) } ?? 1000
        func frameCamera() {
            controller.place(view)
            if let zoom = options["zoom"].flatMap({ Double($0) }) { controller.cameraNode.camera?.orthographicScale = zoom }
            if let lift = options["lift"].flatMap({ Double($0) }) { controller.cameraNode.position.y += CGFloat(lift) }
        }

        // record=<seconds>: write a PNG sequence (out path is a directory) while
        // tying from `from` to the notation. Timed changes: at=<sec>:<key>=<value>
        // with keys goal, tight, spread, cloth, display; orbit=<degrees> swings
        // the camera around the knot over the whole recording.
        if let seconds = options["record"].flatMap({ Double($0) }) {
            let fps = options["fps"].flatMap { Double($0) } ?? 25
            var events: [(time: Double, key: String, value: String)] = []
            for arg in args.dropFirst(2) where arg.hasPrefix("at=") {
                let parts = arg.dropFirst(3).split(separator: ":", maxSplits: 1).map(String.init)
                let pair = parts.count == 2 ? parts[1].split(separator: "=", maxSplits: 1).map(String.init) : []
                if pair.count == 2, let time = Double(parts[0]) { events.append((time, pair[0], pair[1])) }
            }
            try FileManager.default.createDirectory(atPath: args[0], withIntermediateDirectories: true)
            controller.set(goal: KnotProgram(options["from"] ?? ""), full: program)
            controller.settle()
            frameCamera()
            let home = controller.cameraNode.position
            let target = controller.orbitTarget
            let hold = options["wait"].flatMap { Double($0) } ?? 0.6
            var time = -hold, frame = 0, started = false
            while time < seconds {
                if !started && time >= 0 { controller.set(goal: program, full: program); started = true }
                for event in events where event.time <= time && event.time > time - 1 / fps {
                    switch event.key {
                    case "goal": controller.set(goal: KnotProgram(event.value), full: program)
                    case "tight": params.tightness = Double(event.value) ?? params.tightness; controller.set(params: params)
                    case "spread": params.layerSpread = Double(event.value) ?? 1; controller.set(params: params)
                    case "cloth":
                        fabric.cloth = ClothKind.allCases.first { $0.rawValue.lowercased().replacingOccurrences(of: " ", with: "").hasPrefix(event.value) } ?? .twill
                        params.weight = fabric.cloth.weight; controller.set(params: params); controller.apply(fabric: fabric)
                    case "display":
                        fabric.display = FabricDisplay.allCases.first { $0.rawValue.lowercased() == event.value } ?? .fabric
                        controller.apply(fabric: fabric)
                    default: break
                    }
                }
                for _ in 0..<4 { controller.advance(1 / (fps * 4)) }
                if let degrees = options["orbit"].flatMap({ Double($0) }) {
                    let phase = max(0, time) / seconds
                    let angle = degrees * Double.pi / 180 * sin(phase * 2 * Double.pi)
                    let dx = Double(home.x - target.x), dz = Double(home.z - target.z)
                    controller.cameraNode.position = SCNVector3(Double(target.x) + dx * cos(angle) + dz * sin(angle), Double(home.y), Double(target.z) - dx * sin(angle) + dz * cos(angle))
                    controller.cameraNode.look(at: SCNVector3(target.x, home.y, target.z))
                }
                let image = controller.snapshot(size: NSSize(width: side, height: side))
                if let png = KnotSceneController.png(image) {
                    try png.write(to: URL(fileURLWithPath: args[0]).appendingPathComponent(String(format: "f%04d.png", frame)))
                }
                frame += 1; time += 1 / fps
            }
            print("\(frame) frames → \(args[0])")
            return
        }

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
        frameCamera()
        let image = controller.snapshot(size: NSSize(width: side, height: side))
        guard let png = KnotSceneController.png(image) else { print("could not encode"); exit(1) }
        try png.write(to: URL(fileURLWithPath: args[0]))
        print("\(program.notation.isEmpty ? "(untied)" : program.notation) → \(args[0])  rows \(controller.sim.mesh.rowCount)  triangles \(controller.sim.mesh.triangleCount)  free end \(String(format: "%.1f", controller.sim.freeLength)) cm")
    }
}

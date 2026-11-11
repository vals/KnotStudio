import AppKit
import SceneKit

/// `KnotStudio --record <dir>` plays a few scripted sessions in the real
/// window and writes every frame of the whole interface as a PNG sequence,
/// one folder per session (Scripts/gifs.sh turns them into GIFs).
///
/// The model is stepped by a fixed clock rather than by the display, so the
/// recordings are smooth and repeatable however long a frame takes to save.
@MainActor
final class Recorder {
    struct Session {
        var name: String
        /// Notation the session starts from, already tied and at rest.
        var start: String
        var seconds: Double
        var zoom: Double
        var lift: Double
        var actions: [(time: Double, run: (StudioModel) -> Void)]
    }

    static let fps = 15.0
    let directory: URL
    private var sessions: [Session] = []

    init(directory: String) { self.directory = URL(fileURLWithPath: directory) }

    func start() {
        // Typing a sequence character by character shows the live parsing.
        func typing(_ text: String, from start: Double, every interval: Double) -> [(time: Double, run: (StudioModel) -> Void)] {
            var actions: [(time: Double, run: (StudioModel) -> Void)] = []
            var typed = ""
            var time = start
            for character in text {
                typed.append(character)
                if character == " " { continue }
                let snapshot = typed
                actions.append((time, { $0.typed(snapshot) }))
                time += interval
            }
            return actions
        }
        func move(_ region: Region, _ inward: Bool) -> (StudioModel) -> Void { { $0.add(Move(region: region, inward: inward)) } }
        sessions = [
            Session(name: "app-build", start: "", seconds: 11.5, zoom: 10.5, lift: -2, actions: [
                (0.8, move(.L, true)), (2.3, move(.R, false)), (3.8, move(.L, true)), (5.3, move(.C, false)), (7.0, { $0.tuck() }),
            ]),
            Session(name: "app-type", start: "", seconds: 15, zoom: 10.5, lift: -2,
                    actions: typing("Li Co Ri Lo Ci Ro Li Co T", from: 0.6, every: 0.42)),
            Session(name: "app-explore", start: "Li Ro Ci Lo Ri Co T", seconds: 13, zoom: 9, lift: -1, actions: [
                (0.8, { $0.fabric.cloth = .wool }),
                (2.4, { $0.fabric.pattern = .dots }),
                (3.8, { $0.fabric.pattern = .stripes; $0.fabric.cloth = .twill }),
                (5.0, { $0.fabric.display = .faces }),
                (6.6, { $0.fabric.display = .fabric }),
                (7.4, { $0.show(step: 3) }),
                (10.4, { $0.show(step: 4) }),
            ]),
        ]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.begin(0) }
    }

    private func begin(_ index: Int) {
        guard let model = StudioModel.current, let view = model.sceneView else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.begin(index) }
            return
        }
        guard index < sessions.count else { NSApp.terminate(nil); return }
        let session = sessions[index]
        let controller = model.controller
        controller.externalClock = true
        model.fabric = FabricSettings()
        model.typed(session.start)
        controller.settle()
        model.camera = .knot
        controller.cameraNode.camera?.orthographicScale = session.zoom
        controller.cameraNode.position.y += CGFloat(session.lift)
        view.pointOfView = controller.cameraNode
        model.show(stats: controller.currentStats)
        let folder = directory.appendingPathComponent(session.name)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        frame(0, of: session, at: index, into: folder, model: model)
    }

    private func frame(_ number: Int, of session: Session, at index: Int, into folder: URL, model: StudioModel) {
        let time = Double(number) / Recorder.fps
        guard time < session.seconds else { begin(index + 1); return }
        for action in session.actions where action.time >= time - 1e-9 && action.time < time + 1 / Recorder.fps - 1e-9 {
            action.run(model)
        }
        for _ in 0..<4 { model.controller.advance(1 / (Recorder.fps * 4)) }
        model.show(stats: model.controller.currentStats)
        // Let the interface redraw with the new state before capturing it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            if let data = self.capture(model) {
                try? data.write(to: folder.appendingPathComponent(String(format: "f%04d.png", number)))
            }
            self.frame(number + 1, of: session, at: index, into: folder, model: model)
        }
    }

    /// The window's interface with the 3D view drawn into its place (the 3D
    /// view is not part of what AppKit can cache, so it is captured separately).
    private func capture(_ model: StudioModel) -> Data? {
        guard let view = model.sceneView, let content = view.window?.contentView else { return nil }
        let bounds = content.bounds
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width), pixelsHigh: Int(bounds.height),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        bitmap.size = bounds.size
        content.cacheDisplay(in: bounds, to: bitmap)
        var rect = view.convert(view.bounds, to: content)
        if content.isFlipped { rect.origin.y = bounds.height - rect.maxY }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        view.snapshot().draw(in: rect, from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}

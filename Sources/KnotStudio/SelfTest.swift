import AppKit
import SceneKit

/// `KnotStudio --selftest <dir>` drives the real window through a short tying
/// session and writes what the view shows, plus frame timings, to <dir>.
/// It exists so the live path (render-thread stepping, geometry swaps, idle
/// and wake) can be checked without anyone operating the UI.
@MainActor
final class SelfTest {
    let directory: URL
    private var log: [String] = []
    private var script: [(delay: Double, name: String, action: (StudioModel) -> Void)] = []

    init(directory: String) { self.directory = URL(fileURLWithPath: directory) }

    func start() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        script = [
            (1.5, "01-start-four-in-hand", { _ in }),
            (0.1, "", { $0.clear() }),
            (6.0, "02-untied", { _ in }),
            (0.1, "", { $0.add(Move(region: .L, inward: true)) }),
            (0.35, "03-Li-in-motion", { _ in }),
            (2.2, "04-Li-at-rest", { _ in }),
            (0.1, "", { $0.add(Move(region: .R, inward: false)) }),
            (0.45, "05-Ro-in-motion", { _ in }),
            (2.2, "06-Ro-at-rest", { _ in }),
            // Keyboard: finish the four-in-hand with real key events.
            (0.1, "", { _ in SelfTest.press("l", 37) }),
            (1.5, "", { _ in SelfTest.press("c", 8) }),
            (2.0, "", { _ in SelfTest.press("t", 17) }),
            (1.2, "06b-keys-threading", { _ in }),
            (3.5, "06c-keys-dressed", { _ in }),
            (0.1, "", { $0.fabric.cloth = .wool }),
            (1.5, "06d-wool", { _ in }),
            (0.1, "", { $0.fabric.cloth = .twill }),
            (0.1, "", { $0.typed("Li Co Ri Lo Ci Ro Li Co T") }),
            (1.2, "07-windsor-in-motion", { _ in }),
            (16.0, "08-windsor-at-rest", { _ in }),
            (0.1, "", { $0.show(step: 4) }),
            (4.0, "09-windsor-step-4", { _ in }),
            (0.1, "", { $0.fabric.display = .faces; $0.params.tightness = 0.3 }),
            (2.0, "10-loose-faces", { _ in }),
            (0.1, "", { $0.typed("Lo Ci Lo Ri Co T"); $0.fabric.display = .fabric; $0.params.tightness = 0.85; $0.camera = .portrait }),
            (14.0, "11-pratt-portrait", { _ in }),
        ]
        // A window that is hidden or on a sleeping display gets no redraw
        // callbacks, so the test would see nothing move. Drive the same frame
        // function from a timer in that case and say so in the log.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let model = StudioModel.current, !model.windowVisible else { return }
            self.log.append("window not visible: frames driven by a 60 Hz timer instead of the display")
            let controller = model.controller
            Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
                // Only while hidden; once the display drives frames, stay out of its way.
                MainActor.assumeIsolated { if !model.windowVisible { controller.tick(CACurrentMediaTime()) } }
            }
        }
        run(0)
    }

    static func press(_ character: String, _ keyCode: UInt16) {
        guard let window = NSApp.windows.first, let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: character,
            charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode) else { return }
        NSApp.postEvent(event, atStart: false)
    }

    private func run(_ index: Int) {
        guard let model = StudioModel.current else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.run(index) }
            return
        }
        guard index < script.count else { finish(model); return }
        let item = script[index]
        DispatchQueue.main.asyncAfter(deadline: .now() + item.delay) {
            item.action(model)
            if !item.name.isEmpty {
                let controller = model.controller
                if let data = model.snapshotPNG() { try? data.write(to: self.directory.appendingPathComponent(item.name + ".png")) }
                self.log.append("\(item.name): shown “\(model.shownProgram.notation)” step \(model.step)/\(model.program.stepCount), idle \(controller.isIdle), redrawing \(model.isRendering), window visible \(model.windowVisible), frames \(controller.liveFrames)")
            }
            self.run(index + 1)
        }
    }

    private func finish(_ model: StudioModel) {
        let c = model.controller
        let frames = max(c.liveFrames, 1)
        log.append(String(format: "live frames stepped: %d over %.1f s of motion (%.0f per second)", c.liveFrames, c.liveSeconds, Double(c.liveFrames) / max(c.liveSeconds, 1e-3)))
        log.append(String(format: "simulation + meshing: mean %.3f ms, worst %.3f ms per frame", c.liveMillisTotal / Double(frames), c.liveMillisWorst))
        try? log.joined(separator: "\n").write(to: directory.appendingPathComponent("selftest.txt"), atomically: true, encoding: .utf8)
        // The interface itself (the 3D view is captured separately above).
        if let content = NSApp.windows.first?.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("window.png"))
        }
        NSApp.terminate(nil)
    }
}

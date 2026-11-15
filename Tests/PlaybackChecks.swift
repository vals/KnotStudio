import AppKit
import Foundation
import SceneKit

/// Model-level regression checks. No app window, file dialogs or user data.
@main struct PlaybackChecks {
    @MainActor static func main() {
        let model = StudioModel()
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.35)) }
        func pending() {
            model.typed("Li Ro Li Co T")
            model.play()
            model.controller.onActivity?(false)
        }

        pending()
        drain()
        expect(model.step == 1 && model.playing, "Replay advances one settled step")
        model.stop()

        pending()
        model.controller.onActivity?(false)
        model.controller.onActivity?(false)
        drain()
        expect(model.step == 1, "Duplicate rest notifications must not skip steps")

        pending()
        model.stop()
        drain()
        expect(model.step == 0 && !model.playing, "Stop cancels queued advancement")

        pending()
        model.stop()
        model.play()
        drain()
        expect(model.step == 0 && model.playing, "Old callback must not advance restarted playback")
        model.controller.onActivity?(false)
        drain()
        expect(model.step == 1, "Restart still advances on its own rest notification")

        pending()
        model.show(step: 3)
        drain()
        expect(model.step == 3 && !model.playing, "Scrubbing cancels queued advancement")

        pending()
        model.clear()
        drain()
        expect(model.step == 0 && model.program.stepCount == 0, "Clear cannot resurrect playback")

        pending()
        model.typed("Li Ro")
        drain()
        expect(model.step == 2 && !model.playing, "Editing replaces playback")

        pending()
        model.typed("Li Ro Li Co T ")
        drain()
        expect(model.step == 0 && !model.playing, "Even equivalent text edits stop playback")

        pending()
        model.controller.onActivity?(true)
        drain()
        expect(model.step == 0 && model.playing, "Resumed motion invalidates old rest delay")
        model.controller.onActivity?(false)
        drain()
        expect(model.step == 1, "New rest starts a fresh delay")

        model.typed("Li Ro")
        model.play()
        for expected in 1...2 {
            model.controller.onActivity?(false)
            drain()
            expect(model.step == expected, "Playback advances in sequence")
        }
        expect(!model.playing, "Final step ends playback")
        model.controller.onActivity?(false)
        drain()
        expect(model.step == 2, "Finished replay does not overshoot")
        // An offscreen view verifies renderer state; no window is shown.
        let view = SCNView(frame: .zero)
        model.attach(view)
        model.play()
        model.controller.settle()
        for frame in 0..<30 { model.controller.tick(Double(frame) / 60) }
        expect(model.controller.isIdle, "Test setup reaches controller rest")
        model.stop()
        expect(!view.rendersContinuously, "Stopping at rest must stop continuous rendering")
        drain()
        model.play()
        expect(view.rendersContinuously, "Restart wakes the renderer")
        model.stop()
        print("Passed \(checks) playback checks")
    }
}

import AppKit
import SceneKit
import SwiftUI

/// UI state. The notation text is the "program"; `step` selects how much of it
/// is tied, so a partial knot is just a prefix of the program.
@MainActor
final class StudioModel: ObservableObject {
    let controller = KnotSceneController()
    private weak var view: SCNView?

    @Published var text: String
    @Published private(set) var program: KnotProgram
    @Published private(set) var step: Int
    @Published private(set) var issue: String?
    @Published var fabric = FabricSettings() { didSet { controller.apply(fabric: fabric) } }
    @Published var params = KnotParams() { didSet { controller.set(params: params); wake() } }
    @Published var camera: CameraPreset = .knot { didSet { placeCamera() } }
    @Published private(set) var stats = SimStats()
    @Published private(set) var playing = false
    @Published var imageName = ""
    @Published var fileError = ""

    /// The window's model, for the launch-argument self-test.
    static weak var current: StudioModel?

    init(notation: String = "Li Ro Li Co T") {
        let parsed = KnotProgram.parse(notation)
        text = parsed.program.notation
        program = parsed.program
        step = parsed.program.stepCount
        issue = parsed.issue
        controller.set(goal: parsed.program)
        controller.set(params: params)
        controller.onStats = { [weak self] stats in self?.stats = stats }
        controller.onActivity = { [weak self] moving in self?.activity(moving) }
        StudioModel.current = self
    }

    /// Snapshot of the live view, exactly as displayed.
    func snapshotPNG() -> Data? { view.flatMap { KnotSceneController.png($0.snapshot()) } }

    // MARK: Knot editing

    var shownProgram: KnotProgram { program.prefix(step) }
    var knotName: String? { NamedKnot.name(for: program) }
    var nextMoves: [Move] { KnotProgram.nextMoves(after: shownProgram.moves) }
    var canTuck: Bool { !shownProgram.tuck && KnotProgram.canTuck(shownProgram.moves) }
    var canAddMoves: Bool { !shownProgram.tuck }

    func objection(to move: Move) -> String? {
        shownProgram.tuck ? "The knot is finished. Step back to change it." : KnotProgram.objection(to: move, after: shownProgram.moves)
    }

    /// Called as the user types in the notation field.
    func typed(_ newText: String) {
        text = newText
        let parsed = KnotProgram.parse(newText)
        issue = parsed.issue
        guard parsed.program != program else { return }
        playing = false
        program = parsed.program
        step = program.stepCount
        push()
    }

    func load(_ knot: NamedKnot) { replace(with: knot.program) }

    func add(_ move: Move) {
        guard objection(to: move) == nil else { return }
        var next = shownProgram
        next.moves.append(move)
        replace(with: next)
    }

    func tuck() {
        guard canTuck else { return }
        var next = shownProgram
        next.tuck = true
        replace(with: next)
    }

    func undo() {
        var next = shownProgram
        if next.tuck { next.tuck = false } else if !next.moves.isEmpty { next.moves.removeLast() }
        replace(with: next)
    }

    func clear() { replace(with: KnotProgram()) }

    private func replace(with next: KnotProgram) {
        playing = false
        program = next
        step = next.stepCount
        text = next.notation
        issue = nil
        push()
    }

    func show(step newStep: Int) {
        playing = false
        step = max(0, min(newStep, program.stepCount))
        push()
    }

    /// Untie, then tie the whole program one step at a time.
    func play() {
        guard program.stepCount > 0 else { return }
        step = 0
        push()
        playing = true
    }

    func stop() { playing = false }

    private func push() {
        controller.set(goal: shownProgram, full: program)
        wake()
    }

    // MARK: View plumbing

    func attach(_ view: SCNView) {
        self.view = view
        placeCamera()
    }

    /// The simulation is stepped from the view's render callback, so the view
    /// must redraw continuously while anything moves and may rest otherwise.
    private func wake() { view?.rendersContinuously = true; view?.isPlaying = true }
    private func rest() { view?.rendersContinuously = false; view?.isPlaying = false }
    var isRendering: Bool { view?.rendersContinuously ?? false }
    var windowVisible: Bool { view?.window?.occlusionState.contains(.visible) ?? false }

    private func activity(_ moving: Bool) {
        if moving { return }
        if playing {
            if step < program.stepCount {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self, self.playing else { return }
                    self.step += 1
                    self.push()
                    if self.step >= self.program.stepCount { self.playing = false }
                }
            } else { playing = false }
            return
        }
        // Nothing left to animate: let the view stop redrawing.
        if controller.isIdle { rest() }
    }

    func placeCamera() {
        controller.place(camera)
        guard let view else { return }
        view.pointOfView = controller.cameraNode
        view.defaultCameraController.target = controller.orbitTarget
        view.setNeedsDisplay(view.bounds)
    }

    // MARK: Files

    func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            fabric.image = try FabricImage.load(url)
            fabric.pattern = .imported
            fabric.display = .fabric
            imageName = url.lastPathComponent
        } catch { fileError = error.localizedDescription }
    }

    func clearImage() {
        fabric.image = nil
        imageName = ""
        if fabric.pattern == .imported { fabric.pattern = .stripes }
    }

    func exportImage() {
        guard let view else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let name = (knotName ?? (program.compact.isEmpty ? "untied" : program.compact))
        panel.nameFieldStringValue = "\(name).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let data = KnotSceneController.png(view.snapshot()) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
        } catch { fileError = error.localizedDescription }
    }
}

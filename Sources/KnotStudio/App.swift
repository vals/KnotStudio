import AppKit
import SceneKit
import SwiftUI

@main
struct KnotStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("Knot Studio") { ContentView().frame(minWidth: 1040, minHeight: 720) }
            .windowStyle(.hiddenTitleBar)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.setContentSize(NSSize(width: 1240, height: 860))
        NSApp.windows.first?.center()
        if let index = CommandLine.arguments.firstIndex(of: "--selftest"), index + 1 < CommandLine.arguments.count {
            SelfTest(directory: CommandLine.arguments[index + 1]).start()
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct KnotView: NSViewRepresentable {
    let model: StudioModel
    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = model.controller.scene
        view.delegate = model.controller
        view.pointOfView = model.controller.cameraNode
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = KnotSceneController.background
        view.autoenablesDefaultLighting = false
        view.preferredFramesPerSecond = 120
        view.rendersContinuously = true
        model.attach(view)
        return view
    }
    func updateNSView(_ view: SCNView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var model = StudioModel()
    @State private var showAbout = false

    private let paper = Color(nsColor: NSColor(srgbRed: 0.95, green: 0.94, blue: 0.91, alpha: 1))
    private let stage = Color(nsColor: KnotSceneController.background)

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    knotSection
                    fabricSection
                    viewSection
                    Button("How the model works") { showAbout = true }
                        .buttonStyle(.plain).foregroundStyle(.secondary).font(.caption)
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
            .frame(width: 356)
            .background(paper)
            stageView
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showAbout) { about }
        .alert("File operation failed", isPresented: Binding(get: { !model.fileError.isEmpty }, set: { if !$0 { model.fileError = "" } })) {
            Button("OK") { model.fileError = "" }
        } message: { Text(model.fileError) }
    }

    // MARK: Sidebar

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("KNOT STUDIO").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2.4).foregroundStyle(.secondary)
            Text("Tie it move by move.").font(.system(size: 27, weight: .semibold, design: .serif))
            Text("Any knot from its notation, live").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.top, 18)
    }

    private var knotSection: some View {
        section("01  THE KNOT") {
            HStack {
                Menu(model.knotName ?? "Named knots") {
                    ForEach(NamedKnot.catalog) { knot in
                        Button("\(knot.name)  ·  \(knot.notation)") { model.load(knot) }
                    }
                }
                .fixedSize()
                Spacer()
                if model.program.isClassical {
                    Text("Fink–Mao knot").font(.caption2).foregroundStyle(.secondary)
                } else if model.program.tuck {
                    Text("off-catalogue").font(.caption2).foregroundStyle(.secondary)
                }
            }
            TextField("Li Ro Li Co T", text: Binding(get: { model.text }, set: { model.typed($0) }))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
            if let issue = model.issue {
                Text(issue).font(.caption).foregroundStyle(Color(red: 0.72, green: 0.26, blue: 0.12)).fixedSize(horizontal: false, vertical: true)
            }
            timeline
            Text(stepCaption).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 30, alignment: .topLeading)
            movePad
        }
    }

    private var stepCaption: String {
        if model.step == 0 { return model.program.stepCount == 0 ? "Draped and untied. Add a move below, or type a sequence." : "Draped and untied." }
        return "\(model.step). " + model.program.describe(step: model.step - 1)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            let tokens = model.program.tokens
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 5)], alignment: .leading, spacing: 5) {
                chip("∅", active: true, current: model.step == 0) { model.show(step: 0) }
                ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                    chip(token, active: index < model.step, current: index + 1 == model.step) { model.show(step: index + 1) }
                }
            }
            HStack(spacing: 8) {
                Button { model.show(step: model.step - 1) } label: { Image(systemName: "chevron.left") }
                    .disabled(model.step == 0).help("One step back")
                Button { model.show(step: model.step + 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(model.step >= model.program.stepCount).help("One step forward")
                Button { model.playing ? model.stop() : model.play() } label: {
                    Label(model.playing ? "Stop" : "Tie from the start", systemImage: model.playing ? "stop.fill" : "play.fill")
                }
                .disabled(model.program.stepCount == 0)
                Spacer()
                Text("\(model.step) of \(model.program.stepCount)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            .controlSize(.small)
        }
    }

    private func chip(_ label: String, active: Bool, current: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: current ? .bold : .medium, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 24)
                .foregroundStyle(active ? Color.white : Color.primary.opacity(0.45))
                .background(RoundedRectangle(cornerRadius: 5).fill(active ? Color(red: 0.10, green: 0.22, blue: 0.33).opacity(current ? 1 : 0.72) : Color.black.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private var movePad: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NEXT MOVE").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(.secondary)
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    Text("").frame(width: 46)
                    ForEach([Region.L, .C, .R], id: \.self) { region in
                        Text(region == .L ? "left" : (region == .R ? "right" : "centre")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                ForEach([true, false], id: \.self) { inward in
                    GridRow {
                        Text(inward ? "in front" : "behind").font(.caption2).foregroundStyle(.secondary).frame(width: 46, alignment: .leading)
                        ForEach([Region.L, .C, .R], id: \.self) { region in
                            let move = Move(region: region, inward: inward)
                            let objection = model.objection(to: move)
                            Button { model.add(move) } label: {
                                Text(move.token).font(.system(size: 13, weight: .semibold, design: .monospaced)).frame(maxWidth: .infinity)
                            }
                            .disabled(objection != nil)
                            .help(objection ?? KnotProgram(moves: model.shownProgram.moves + [move]).describe(step: model.shownProgram.moves.count))
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Button { model.tuck() } label: { Text("T  tuck").font(.system(size: 13, weight: .semibold, design: .monospaced)).frame(maxWidth: .infinity) }
                    .disabled(!model.canTuck)
                    .help(model.canTuck ? "Tuck the wide end down through the front band." : "A tuck follows Co, once there is a band across the front.")
                Button { model.undo() } label: { Label("Undo", systemImage: "delete.left") }.disabled(model.step == 0)
                Button("Clear") { model.clear() }.disabled(model.program.stepCount == 0)
            }
            Text("Keys: L R C make the next move (Shift on the first move starts inside-out) · T tuck · ⌫ undo · ← → step · space replay")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fabricSection: some View {
        section("02  THE FABRIC") {
            Picker("Pattern", selection: $model.fabric.pattern) {
                ForEach(FabricPattern.allCases.filter { $0 != .imported || model.fabric.image != nil }) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            Picker("Cloth", selection: $model.fabric.cloth) {
                ForEach(ClothKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .help("Thicker cloth ties a bulkier knot from the same moves.")
            HStack {
                ColorPicker("Ground", selection: color(\.base), supportsOpacity: false)
                ColorPicker("Detail", selection: color(\.accent), supportsOpacity: false)
            }
            .font(.caption)
            slider("Repeat width", value: $model.fabric.repeatCM, range: 1...9, format: "%.1f cm")
            slider("Offset along the tie", value: $model.fabric.offsetCM, range: 0...20, format: "%.1f cm")
            slider("Pattern angle", value: $model.fabric.angle, range: -90...90, format: "%.0f°")
            HStack {
                Button { model.importImage() } label: { Label("Import swatch…", systemImage: "photo") }
                if model.fabric.image != nil { Button("Clear") { model.clearImage() } }
            }
            .controlSize(.small)
            if !model.imageName.isEmpty {
                Text("\(model.imageName) · reverse shown neutral").font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private var viewSection: some View {
        section("03  LOOK CLOSER") {
            slider("Tightness", value: $model.params.tightness, range: 0...1, format: "%.2f")
            slider("Layer separation", value: $model.params.layerSpread, range: 1...4, format: "%.1f×")
            Toggle("Balance the two ends for this knot", isOn: $model.params.autoBalance).font(.caption)
            if model.params.autoBalance {
                Text(String(format: "Narrow end %.0f cm below the knot", model.stats.narrowEnd)).font(.caption2).foregroundStyle(.secondary)
            } else {
                slider("Narrow end length", value: $model.params.narrowEnd, range: 14...60, format: "%.0f cm")
            }
            slider("Tying speed", value: $model.params.speed, range: 0.25...3, format: "%.2f×")
            Picker("Display", selection: $model.fabric.display) {
                ForEach(FabricDisplay.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            Toggle("Shirt collar (folds down when the knot is dressed)", isOn: $model.showCollar).font(.caption)
            Text("Grid shows the cloth’s own coordinates. Faces: teal is the front of the fabric, rust the back.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func color(_ path: WritableKeyPath<FabricSettings, NSColor>) -> Binding<Color> {
        Binding(get: { Color(nsColor: model.fabric[keyPath: path]) }, set: { model.fabric[keyPath: path] = NSColor($0) })
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.4).foregroundStyle(.secondary)
            content()
        }
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: format, value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.caption)
            Slider(value: value, in: range)
        }
    }

    // MARK: Stage

    private var stageView: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.knotName ?? (model.program.stepCount == 0 ? "Untied" : "Custom knot"))
                        .font(.system(size: 22, weight: .medium, design: .serif)).foregroundStyle(.white)
                    Text(model.shownProgram.notation.isEmpty ? "NO MOVES YET" : model.shownProgram.notation.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Color.white.opacity(0.5))
                }
                Spacer()
                Picker("Camera", selection: $model.camera) {
                    ForEach(CameraPreset.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 270)
                Button { model.placeCamera() } label: { Image(systemName: "arrow.counterclockwise") }.help("Reset the camera")
                Button { model.exportImage() } label: { Image(systemName: "square.and.arrow.up") }.help("Export the current view as a PNG")
            }
            .padding(22)
            KnotView(model: model)
            HStack {
                Label("Drag to orbit · scroll to zoom", systemImage: "move.3d")
                Spacer()
                Text(statusLine).monospacedDigit()
            }
            .font(.caption).foregroundStyle(Color.white.opacity(0.55)).padding(.horizontal, 22).padding(.vertical, 14)
        }
        .background(stage)
        // The window is light (for the paper sidebar) but the stage is dark;
        // its controls need the dark appearance to stay legible.
        .environment(\.colorScheme, .dark)
    }

    private var statusLine: String {
        let cost = String(format: "%.2f ms per step", model.stats.stepMillis)
        let size = "\(model.stats.triangles / 1000)k triangles"
        let free = String(format: "wide end %.0f cm free", model.stats.freeLength)
        return "\(model.stats.moving ? "tying" : "at rest") · \(cost) · \(size) · \(free)"
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A folded ribbon, not a cloth solver").font(.title2.weight(.semibold))
            Text("The notation says exactly how the wide end winds around the narrow end: each move is one pass across the front or the back, ending at a fold on the left, on the right or over the top. Knot Studio builds that winding directly. Later passes always lie outside earlier ones, so which layer covers which is known in advance and nothing has to be detected or untangled.")
            Text("Each pass is a flat panel of the tie’s own fabric and each fold is a roll around a straight crease, so the pattern is carried through the knot without stretching: stripes turn where the cloth turns and flip where it flips. Where the tie is wider than the knot, the extra is rolled under at the edges, as it is in a real knot.")
            Text("Only the free wide end is simulated as a hanging chain; it swings and is carried around as you add or remove moves. Tightness, cushioning and taper are shaping applied on top. This shows structure, overlap and pattern placement. It is not a prediction of how a particular silk drapes.")
            Text("View is the mirror view used by Fink and Mao: narrow end on the left, moves named for where the wide end arrives (L, R, C) and where it points next (i into the shirt, o out of it).").foregroundStyle(.secondary)
            Link("Denne, Joireman & Young · The Mathematics of Tie Knots", destination: URL(string: "https://arxiv.org/abs/2005.13000")!)
            Button("Done") { showAbout = false }.keyboardShortcut(.defaultAction)
        }
        .font(.body).padding(30).frame(width: 620)
    }
}

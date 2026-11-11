import SwiftUI
import AppKit
import SceneKit

@main
struct KnotStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("Knot Studio") { ContentView().frame(minWidth:1040,minHeight:740) }
        .windowStyle(.hiddenTitleBar)
        .commands { CommandGroup(replacing:.newItem) {} }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps:true)
        NSApp.windows.first?.setContentSize(NSSize(width:1220,height:860))
        NSApp.windows.first?.center()
        if let pathIndex = CommandLine.arguments.firstIndex(of:"--render-gallery"), pathIndex+1 < CommandLine.arguments.count {
            let output = CommandLine.arguments[pathIndex+1]
            DispatchQueue.main.asyncAfter(deadline:.now()+1) {
                do { try Self.renderGallery(output); NSApp.terminate(nil) } catch { print(error); exit(1) }
            }
        }
    }
    static func renderGallery(_ directory: String) throws {
        try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
        for knot in KnotKind.allCases {
            for diagnostic in [false,true] {
                var settings = SceneSettings(); settings.knot = knot; settings.camera = "Knot"
                if diagnostic { settings.fabric.pattern = .ruler; settings.fabric.angle = 0; settings.spread = 1.4; settings.showPath = true }
                let scene = SceneFactory.make(settings), renderer = SCNRenderer(device:nil,options:nil)
                renderer.scene = scene; renderer.pointOfView = scene.rootNode.childNode(withName:"camera",recursively:false)
                let image = renderer.snapshot(atTime:0,with:NSSize(width:1100,height:1000),antialiasingMode:.multisampling4X)
                let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
                let name = knot.rawValue.lowercased().replacingOccurrences(of:" ",with:"-") + (diagnostic ? "-routing" : "-fabric") + ".png"
                try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:directory).appendingPathComponent(name))
            }
        }
        print("Rendered 8 SceneKit snapshots to \(directory)")
    }
}

struct ContentView: View {
    @State private var knot: KnotKind = .fourInHand
    @State private var pattern: FabricPattern = .stripes
    @State private var fabricView=FabricViewState()
    @State private var base = Color(red:0.08,green:0.18,blue:0.28)
    @State private var accent = Color(red:0.88,green:0.63,blue:0.28)
    @State private var repeatCM = 3.6
    @State private var offsetCM = 0.0
    @State private var angle = 32.0
    @State private var spread = 0.0
    @State private var showPath = false
    @State private var selectedMove = -1
    @State private var camera = "Knot"
    @State private var reset = 0
    @State private var imported: NSImage?
    @State private var imageName = ""
    @State private var notation = "LiRoLiCoT"
    @State private var notationMessage = ""
    @State private var showAbout = false
    @State private var fileError = ""
    @StateObject private var viewController=StudioViewController()
    var storedFabric:FabricSettings {
        FabricSettings(pattern:pattern,base:NSColor(base),accent:NSColor(accent),repeatCM:repeatCM,offsetCM:offsetCM,angle:angle,image:imported)
    }
    var settings: SceneSettings {
        var s = SceneSettings(); s.knot = knot; s.spread = spread; s.showPath = showPath; s.selectedMove = selectedMove; s.camera = camera; s.reset = reset
        s.fabric = fabricView.displayedFabric(from:storedFabric)
        return s
    }
    var body: some View {
        TabView {
            authored.tabItem {Text("Preset studio")}
            ClothLabView(fabric:storedFabric).tabItem {Text("Cloth lab · research paused")}
        }
    }
    var authored: some View {
        HStack(spacing:0) {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    VStack(alignment:.leading,spacing:5) {
                        Text("KNOT STUDIO").font(.system(size:11,weight:.bold,design:.monospaced)).tracking(2.4).foregroundStyle(.secondary)
                        Text("Fabric in form.").font(.system(size:29,weight:.semibold,design:.serif))
                        Text("Photo-referenced knot presets").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.top,18)
                    section("01  THE PRESET") {
                        Picker("Knot",selection:$knot) { ForEach(KnotKind.allCases) { Text($0 == .fourInHand ? $0.rawValue : "\($0.rawValue) · experimental").tag($0) } }.labelsHidden()
                        Text(knot.subtitle).font(.caption).foregroundStyle(.secondary)
                        Text(knot.notation).font(.system(size:15,weight:.medium,design:.monospaced)).textSelection(.enabled)
                        Text(knot == .fourInHand ? "Photo-referenced four-in-hand · authored surface" : "Legacy route study · shape not yet photo-referenced").font(.caption2).foregroundStyle(.secondary)
                        Text("Notation identifies a saved preset. It does not generate an arbitrary tied knot.").font(.caption2).foregroundStyle(.secondary)
                        DisclosureGroup("Find preset by notation") {
                            VStack(alignment:.leading,spacing:8) {
                                TextField("LiRoLiCoT",text:$notation).textFieldStyle(.roundedBorder).font(.system(.body,design:.monospaced))
                                Button("Find preset") { validate() }
                                if !notationMessage.isEmpty { Text(notationMessage).font(.caption).fixedSize(horizontal:false,vertical:true) }
                            }.padding(.top,6)
                        }.font(.caption)
                    }
                    section("02  THE FABRIC") {
                        Picker("Pattern",selection:$pattern) {
                            ForEach(FabricPattern.allCases.filter { $0 != .ruler && $0 != .faces && ($0 != .imported || imported != nil) }) { Text($0.rawValue).tag($0) }
                        }.labelsHidden()
                        HStack { ColorPicker("Ground",selection:$base,supportsOpacity:false); ColorPicker("Detail",selection:$accent,supportsOpacity:false) }.font(.caption)
                        slider("Repeat width",value:$repeatCM,range:1...9,unit:"cm")
                        slider("Along-fabric offset",value:$offsetCM,range:0...20,unit:"cm")
                        slider("Pattern angle",value:$angle,range:-90...90,unit:"°")
                        HStack {
                            Button { importImage() } label: { Label("Import swatch…",systemImage:"photo") }
                            if imported != nil { Button("Clear") { imported = nil; pattern = .stripes; imageName = ""; fabricView.mode = .fabric } }
                        }.controlSize(.small)
                        Text(imageName.isEmpty ? "Repeat width is measured on the assumed flat fabric, before folding." : "\(imageName) · reverse unspecified (neutral)").font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        Text(String(format:"Tile repeat: %.1f × %.1f cm",repeatCM,repeatCM*storedFabric.aspect)).font(.caption2).foregroundStyle(.secondary)
                        Button("Reset pattern placement") { repeatCM=3.6; offsetCM=0; angle=32 }.controlSize(.small)
                    }
                    section("03  INSPECT THE FABRIC") {
                        slider("Separate layers",value:$spread,range:0...3,unit:"")
                        if knot != .fourInHand { Toggle("Trace legacy centerline",isOn:$showPath).font(.caption) }
                        Picker("Display",selection:$fabricView.mode) {
                            ForEach(FabricViewMode.allCases) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                        Text("Choose Fabric to return to your swatch. Diagnostic views keep its placement settings.").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        Text("Teal = front · rust = back. Layer separation preserves each panel’s fabric coordinates.").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                    Button("Model & source notes") { showAbout = true }.buttonStyle(.plain).foregroundStyle(.secondary).font(.caption)
                }.padding(.horizontal,24).padding(.bottom,24)
            }.frame(width:345).background(Color(nsColor:NSColor(srgbRed:0.95,green:0.94,blue:0.91,alpha:1)))
            VStack(spacing:0) {
                HStack {
                    VStack(alignment:.leading,spacing:3) {
                        Text(knot.rawValue).font(.system(size:22,weight:.medium,design:.serif)).foregroundStyle(.white)
                        Text(knot == .fourInHand ? "PHOTO-REFERENCED · AUTHORED FOUR-IN-HAND" : "EXPERIMENTAL ROUTE · NOT A TIED PREVIEW").font(.system(size:9,weight:.semibold,design:.monospaced)).tracking(1.5).foregroundStyle(Color.white.opacity(0.5))
                    }
                    Spacer()
                    Picker("Camera",selection:$camera) { Text("Portrait").tag("Portrait"); Text("Knot").tag("Knot"); Text("Side").tag("Side"); Text("Flat").tag("Flat") }.pickerStyle(.segmented).frame(width:270)
                    Button { reset += 1 } label: { Image(systemName:"arrow.counterclockwise") }.help("Reset camera")
                    Button { exportImage() } label: { Image(systemName:"square.and.arrow.up") }.help("Export the current view, including orbit and zoom")
                }.padding(22)
                RibbonScene(settings:settings,controller:viewController)
                HStack {
                    Label("Drag to orbit · scroll to zoom",systemImage:"move.3d")
                    Spacer()
                    Text(camera == "Flat" ? "Flat blade · authored material panel" : (spread > 0 ? "Layers separated for inspection" : "Cloth-space motif scale"))
                }.font(.caption).foregroundStyle(Color.white.opacity(0.55)).padding(.horizontal,22).padding(.vertical,14)
                Text("Authored appearance · hidden assembly approximated").font(.caption2).foregroundStyle(Color.white.opacity(0.42)).padding(.bottom,16)
            }.background(Color(red:0.075,green:0.095,blue:0.12))
        }
        .preferredColorScheme(.light)
        .onChange(of:knot) { value in notation = value.notation; selectedMove = -1; notationMessage = "" }
        .sheet(isPresented:$showAbout) { about }
        .alert("File operation failed",isPresented:Binding(get:{!fileError.isEmpty},set:{ if !$0 { fileError="" } })) { Button("OK") { fileError="" } } message: { Text(fileError) }
    }
    func section<Content:View>(_ title:String,@ViewBuilder content:()->Content) -> some View {
        VStack(alignment:.leading,spacing:11) { Text(title).font(.system(size:10,weight:.semibold,design:.monospaced)).tracking(1.4).foregroundStyle(.secondary); content() }
    }
    func slider(_ label:String,value:Binding<Double>,range:ClosedRange<Double>,unit:String) -> some View {
        VStack(spacing:3) {
            HStack { Text(label); Spacer(); Text(String(format:"%.1f",value.wrappedValue)+(unit.isEmpty ? "" : " \(unit)")).monospacedDigit().foregroundStyle(.secondary) }.font(.caption)
            Slider(value:value,in:range)
        }
    }
    func validate() {
        do {
            let sequence = try TieSequence(notation)
            if let supported = KnotKind.allCases.first(where: { $0.notation == sequence.notation }) {
                knot = supported; notationMessage = supported == .fourInHand ? "Four-in-hand preset selected." : "Legacy experimental route selected. Its tied appearance has not been authored."
            } else { notationMessage = "Recognized notation, but no saved preset is available. The displayed preset has not changed." }
        } catch { notationMessage = error.localizedDescription }
    }
    func importImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png,.jpeg,.tiff,.heic]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do { imported = try FabricImage.load(url); imageName = url.lastPathComponent; pattern = .imported; fabricView.mode = .fabric }
            catch { fileError=error.localizedDescription }
        }
    }
    func exportImage() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "\(knot.rawValue)-preview.png"
        if panel.runModal() == .OK, let url = panel.url {
            do { try viewController.png().write(to:url,options:.atomic) }
            catch { fileError=error.localizedDescription }
        }
    }
    var about: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Photo-referenced knot presets").font(.title2.weight(.semibold))
            Text("Four-in-hand is the first visual milestone: unequal leaning shoulders, one convex wrap and a folded blade with a recessed dimple. Its Li Ro Li Co T notation identifies the preset; notation does not generate arbitrary tied geometry. Other knots retain their experimental route studies.")
            Text("The wrap has a developed material chart, while the blade and neck entries measure fabric across their folded sections. Motifs retain a recognizable cloth-space scale instead of stretching the whole image across every narrow cross-section. The visible panels approximate a tied assembly; hidden regions and seams are not a continuous solved blank.")
            Text("Imported images keep their repeat width, offset, angle and decoded aspect. EXIF orientation is normalized once. At zero angle the image is upright on the flat blade, and the unspecified reverse is neutral gray. Fabric, UV grid and Face identity preserve your selected swatch and placement.")
            Text("This is an authored appearance, not a prediction of a particular fabric’s drape or a topology certificate. Cloth Lab remains available as a separate research experiment; further solver work is paused. These live controls have not been interactively retested in this release; geometry, decoding, state transitions and offscreen pixels were checked.")
            Link("Gentleman’s Gazette · oblique four-in-hand reference",destination:URL(string:"https://www.gentlemansgazette.com/how-to-tie-four-in-hand-knot/")!)
            Link("Ties.com · same-fabric knot comparison",destination:URL(string:"https://www.ties.com/how-to-tie-a-tie")!)
            Link("Denne, Joireman & Young · The Mathematics of Tie Knots (§3)",destination:URL(string:"https://arxiv.org/pdf/2005.13000")!)
            Link("Ties.com · Four-in-hand tying guide",destination:URL(string:"https://www.ties.com/how-to-tie-a-tie/four-in-hand")!)
            Button("Done") { showAbout = false }.keyboardShortcut(.defaultAction)
        }.font(.body).padding(30).frame(width:620)
    }
}

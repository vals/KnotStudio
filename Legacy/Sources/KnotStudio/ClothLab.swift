import SwiftUI
import AppKit
import SceneKit
import simd

private final class ClothCancellation {
    private let lock=NSLock()
    private var stopped=false
    func cancel() {lock.lock();stopped=true;lock.unlock()}
    var value:Bool {lock.lock();defer{lock.unlock()};return stopped}
}

private final class ClothWorker {
    let experiment:ClothExperiment
    var solver:ClothSolver,grasp:ClothGrasp
    let sequence:ClothWrapSequence?
    init(_ experiment:ClothExperiment) {
        self.experiment=experiment;solver=experiment.solver();grasp=experiment.grasp
        sequence=experiment.kind == .wrap ? ClothWrapSequence(mesh:experiment.mesh):nil
    }
    func step(cancelled:()->Bool)->ClothSnapshot {
        if let sequence=sequence {
            if !ClothWrapSequence.isComplete(solver.time) {_=solver.advance(pinTargets:{sequence.targets(at:$0)},cancelled:cancelled)}
        } else {_=solver.advance(cancelled:cancelled)}
        return solver.snapshot()
    }
    func updateGrasp(_ translation:V3,held:Bool) {
        guard sequence==nil else {return}
        if !grasp.held && held {grasp=ClothGrasp(vertices:grasp.vertices,positions:solver.positions)}
        grasp.position+=translation;grasp.held=held
        solver.pins=experiment.fixed.merging(grasp.targets){_,b in b}
    }
}

final class ClothController:ObservableObject {
    @Published private(set) var experiment=ClothExperiment.make(.strip)
    @Published private(set) var snapshot:ClothSnapshot
    @Published private(set) var running=false
    @Published private(set) var busy=false
    @Published private(set) var held=true
    private let queue=DispatchQueue(label:"local.knotstudio.cloth",qos:.userInitiated)
    private var worker:ClothWorker
    private var generation=0
    private var cancellation:ClothCancellation?
    init() {let e=ClothExperiment.make(.strip);worker=ClothWorker(e);snapshot=worker.solver.snapshot()}
    func reset(_ kind:ClothCase) {
        cancellation?.cancel();generation+=1;running=false;busy=false
        let e=ClothExperiment.make(kind);held=e.grasp.held;experiment=e;worker=ClothWorker(e);snapshot=worker.solver.snapshot()
    }
    var sequenceComplete:Bool {experiment.kind == .wrap && ClothWrapSequence.isComplete(snapshot.time)}
    func toggleRun() {if running {pause()} else if !sequenceComplete && snapshot.error==nil {running=true;step()}}
    func pause() {running=false;cancellation?.cancel()}
    func step() {
        guard !busy,!sequenceComplete,snapshot.error==nil else {return}
        busy=true
        let token=generation,w=worker
        let cancellation=ClothCancellation();self.cancellation=cancellation
        queue.async {
            let result=w.step(cancelled:{cancellation.value})
            DispatchQueue.main.async { [weak self] in
                guard let self=self,self.generation==token else {return}
                self.snapshot=result;self.busy=false
                if result.error != nil || self.sequenceComplete {self.running=false}
                if self.running {
                    DispatchQueue.main.asyncAfter(deadline:.now()+1.0/30) { [weak self] in
                        guard let self=self,self.generation==token,self.running else {return};self.step()
                    }
                }
            }
        }
    }
    func grasp(_ translation:V3 = .zero,held:Bool) {
        guard !busy,!running,experiment.kind != .wrap else {return}
        self.held=held;let w=worker
        queue.async {w.updateGrasp(translation,held:held)}
    }
}

struct ClothLabView:View {
    let fabric:FabricSettings
    @StateObject private var controller=ClothController()
    @State private var kind:ClothCase = .strip
    @State private var display=FabricViewState()
    @State private var initial=false
    @State private var camera="Three-quarter"
    @State private var cameraReset=0
    @StateObject private var exportController=StudioViewController()
    @State private var fileError=""
    var body:some View {
        HStack(spacing:0) {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    Text("CLOTH LAB").font(.caption.monospaced()).tracking(2)
                    Text("A material experiment.").font(.system(size:27,weight:.semibold,design:.serif))
                    Picker("Experiment",selection:$kind) {ForEach(ClothCase.allCases){Text($0.rawValue).tag($0)}}.labelsHidden()
                    Text(kind == .strip ? "A 36 cm tapered strip held above a rounded support. Gravity, stretch, shear, bending and contact act on the flat fabric metric." : kind == .fold ? "A folded strip drops onto its held lower section. The free layer must maintain separation while bending and sliding." : kind == .wrap ? "A flat 32 cm strip forms one loose wrap around a rounded support, holds for 0.5 s, then attempts a 5 mm axial slide. Only the end grasps follow scripted paths." : "A refined, contact-prepared four-in-hand seed. Bounded relaxation is experimental; this is not a tying sequence.").font(.caption).foregroundStyle(.secondary)
                    if kind == .fourInHand {
                        Text("A rejected step retains the last checked state. Successful tightening is not established.").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    }
                    HStack {
                        Button(controller.running ? "Pause":"Run") {controller.toggleRun()}.disabled(controller.snapshot.error != nil || controller.sequenceComplete)
                        Button("Step") {controller.step()}.disabled(controller.running || controller.busy || controller.snapshot.error != nil || controller.sequenceComplete)
                        Button("Reset") {controller.reset(kind)}
                    }
                    Text(String(format:"Simulated time %.3f s%@",controller.snapshot.time,controller.busy ? " · computing":"")).font(.caption.monospaced())
                    if kind == .wrap {
                        Text(ClothWrapSequence.phase(controller.snapshot.time)).font(.caption.weight(.semibold))
                        ProgressView(value:min(ClothWrapSequence.duration,controller.snapshot.time),total:ClothWrapSequence.duration)
                        Text("Held contact is the target. Cloth can lag the grasp during sliding; this sequence does not tie a knot.").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(controller.snapshot.collisionStatus).font(.caption).foregroundStyle(controller.snapshot.error == nil ? Color.secondary:.orange)
                    Text("Retries: \(controller.snapshot.retries) · collision evaluations: \(controller.snapshot.collisionEvaluations)").font(.caption2).foregroundStyle(.secondary)
                    if let error=controller.snapshot.error {Text(error).font(.caption).foregroundStyle(.red)}
                    Divider()
                    Text("End grasp").font(.headline)
                    HStack {
                        Button(controller.held ? "Release":"Hold") {controller.grasp(held:!controller.held)}
                        Button("Lift 1 mm") {controller.grasp(V3(0,0.001,0),held:true)}
                        Button("Lower 1 mm") {controller.grasp(V3(0,-0.001,0),held:true)}
                    }.controlSize(.small).disabled(controller.running || controller.busy || kind == .wrap)
                    Text(kind == .wrap ? "The sequence controls both grasps. Reset restores the flat blank and restarts the sequence." : "Pause before moving the grasp. Commands take effect on the next step. Reset restores the original holds and geometry.").font(.caption2).foregroundStyle(.secondary)
                    Divider()
                    Picker("Display",selection:$display.mode) {ForEach(FabricViewMode.allCases){Text($0.rawValue).tag($0)}}.pickerStyle(.segmented)
                    Text("Fabric returns to the swatch selected in Pattern study.").font(.caption2).foregroundStyle(.secondary)
                    Toggle("Compare starting shape",isOn:$initial).font(.caption)
                    Text("The Pattern study tab retains the full authored model.").font(.caption2).foregroundStyle(.secondary)
                    Divider()
                    diagnostics
                    Text("Uncalibrated material. Swept checks cover linear motion between accepted substeps. The support guard includes triangle interiors. Shared-vertex triangle pairs remain excluded; self-contact friction is absent.").font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }.frame(width:350).background(Color(nsColor:.windowBackgroundColor))
            VStack(spacing:0) {
                HStack {
                    Text(initial ? "Starting shape":"Cloth experiment").font(.title2).foregroundStyle(.white)
                    Spacer()
                    Picker("Camera",selection:$camera) {Text("3/4").tag("Three-quarter");Text("Front").tag("Front");Text("Side").tag("Side");if kind == .fourInHand {Text("Knot").tag("Knot")}}.pickerStyle(.segmented).frame(width:270)
                    Button {cameraReset+=1} label:{Image(systemName:"arrow.counterclockwise")}
                    Button {exportImage()} label:{Image(systemName:"square.and.arrow.up")}
                }.padding(22)
                ClothScene(experiment:controller.experiment,snapshot:controller.snapshot,fabric:display.displayedFabric(from:fabric),initial:initial,camera:camera,reset:cameraReset,exportController:exportController)
                Text("Drag to orbit · scroll to zoom · simulation runs in fixed steps, not wall-clock time").font(.caption).foregroundStyle(.white.opacity(0.6)).padding(16)
            }.background(Color(red:0.075,green:0.095,blue:0.12))
        }
        .onChange(of:kind){controller.reset($0);initial=false;camera="Three-quarter"}
        .onDisappear{controller.pause()}
        .alert("Export failed",isPresented:Binding(get:{!fileError.isEmpty},set:{if !$0 {fileError=""}})){Button("OK"){fileError=""}} message:{Text(fileError)}
    }
    var diagnostics:some View {
        let d=controller.snapshot.diagnostics
        return VStack(alignment:.leading,spacing:7) {
            Text("Material deformation").font(.headline)
            Text(String(format:"Warp stretch   %.3f–%.3f×",d.warpMin,d.warpMax))
            Text(String(format:"Weft stretch   %.3f–%.3f×",d.weftMin,d.weftMax))
            Text(String(format:"Max shear      %.1f°",d.shearMax))
            Text(String(format:"RMS strain     %.2f%%",100*d.strainRMS))
            Text(String(format:"Peak speed     %.3f m/s",d.maxSpeed))
            Text("Contact corrections  \(d.contacts)")
            if d.minExternalGap.isFinite {Text(String(format:"Support gap    %.2f mm",1000*d.minExternalGap))}
            Text("1× stretch and 0° shear describe the flat rest metric. Ranges include every coarse triangle.").font(.caption2).foregroundStyle(.secondary)
        }.font(.system(size:11,design:.monospaced))
    }
    private func exportImage() {
        let panel=NSSavePanel();panel.allowedContentTypes=[.png];panel.nameFieldStringValue="cloth-experiment.png"
        if panel.runModal() == .OK,let url=panel.url {do {try exportController.png().write(to:url,options:.atomic)} catch {fileError=error.localizedDescription}}
    }
}

struct ClothScene:NSViewRepresentable {
    let experiment:ClothExperiment,snapshot:ClothSnapshot,fabric:FabricSettings
    let initial:Bool,camera:String,reset:Int
    let exportController:StudioViewController
    func makeCoordinator()->Coordinator {Coordinator()}
    func makeNSView(context:Context)->StudioSCNView {
        let view=StudioSCNView(frame:.zero);view.allowsCameraControl=true;view.antialiasingMode = .multisampling4X
        view.defaultCameraController.interactionMode = .orbitTurntable
        exportController.view=view;return view
    }
    func updateNSView(_ view:StudioSCNView,context:Context) {
        let transform=view.pointOfView?.presentation.transform,lens=view.pointOfView?.camera?.copy() as? SCNCamera
        let pins=initial ? experiment.fixed.merging(experiment.grasp.targets){_,b in b}:snapshot.pins
        let scene=ClothSceneFactory.make(experiment:experiment,positions:initial ? experiment.mesh.initial:snapshot.positions,fabric:fabric,camera:camera,pins:pins)
        view.scene=scene;view.pointOfView=scene.rootNode.childNode(withName:"camera",recursively:false)
        if context.coordinator.kind==experiment.kind && context.coordinator.camera==camera && context.coordinator.reset==reset,let transform=transform {
            view.pointOfView?.transform=transform;if let lens=lens {view.pointOfView?.camera=lens}
        }
        context.coordinator.kind=experiment.kind;context.coordinator.camera=camera;context.coordinator.reset=reset
        view.defaultCameraController.target=camera == "Knot" ? SCNVector3(0,0.5,0):ClothSceneFactory.target(experiment.kind)
    }
    final class Coordinator {var kind:ClothCase?;var camera="";var reset = -1}
}

enum ClothSceneFactory {
    static func target(_ kind:ClothCase)->SCNVector3 {kind == .strip ? SCNVector3(0,13,0):kind == .fold ? SCNVector3(0,15,-5):kind == .wrap ? SCNVector3(0,16,6):SCNVector3(0,-15,0)}
    static func make(experiment:ClothExperiment,positions:[V3],fabric:FabricSettings,camera:String="Three-quarter",pins:[Int:V3]=[:])->SCNScene {
        let scene=SCNScene();scene.background.contents=NSColor(srgbRed:0.075,green:0.095,blue:0.12,alpha:1)
        let mesh=experiment.mesh,count=positions.count
        var normals=[V3](repeating:.zero,count:count)
        for t in mesh.triangles {let ids=t.ids,n=simd_cross(positions[ids[1]]-positions[ids[0]],positions[ids[2]]-positions[ids[0]]);for i in ids {normals[i]+=n}}
        normals=normals.map{unit($0)}
        let front=positions.indices.map{positions[$0]*100+normals[$0]*0.025},back=positions.indices.map{positions[$0]*100-normals[$0]*0.025}
        let chart=mesh.rest.map{RibbonBuilder.uv(transverse:$0.x*100,s:$0.y*100,repeatCM:fabric.repeatCM,offsetCM:fabric.offsetCM,angle:fabric.angle * .pi/180,aspect:fabric.aspect)}
        let sources=[SCNGeometrySource(vertices:(front+back).map(SCNVector3.init)),SCNGeometrySource(normals:(normals+normals.map{-$0}).map(SCNVector3.init)),SCNGeometrySource(textureCoordinates:(chart+chart).map{CGPoint(x:$0.x,y:$0.y)})]
        let fi=mesh.triangles.flatMap{$0.ids.map{Int32($0)}},bi=mesh.triangles.flatMap{$0.ids.reversed().map{Int32($0+count)}}
        let geometry=SCNGeometry(sources:sources,elements:[SCNGeometryElement(indices:fi,primitiveType:.triangles),SCNGeometryElement(indices:bi,primitiveType:.triangles)])
        geometry.materials=[SceneFactory.material(fabric),SceneFactory.material(fabric,back:true)]
        let cloth=SCNNode(geometry:geometry);cloth.name="cloth";scene.rootNode.addChildNode(cloth)
        for i in pins.keys.sorted() where i%5==0 || i%5==4 {
            let marker=SCNNode(geometry:SCNSphere(radius:0.12));marker.position=SCNVector3(pins[i]!*100)
            marker.geometry?.firstMaterial?.diffuse.contents=NSColor.systemOrange;scene.rootNode.addChildNode(marker)
        }
        for shape in experiment.capsules {
            let delta=shape.b-shape.a
            let node=SCNNode(geometry:SCNCapsule(capRadius:shape.radius*100,height:(simd_length(delta)+2*shape.radius)*100))
            node.position=SCNVector3((shape.a+shape.b)*50);node.simdOrientation=simd_quatf(from:SIMD3<Float>(0,1,0),to:SIMD3<Float>(unit(delta)))
            node.geometry?.firstMaterial?.diffuse.contents=NSColor(srgbRed:0.28,green:0.31,blue:0.34,alpha:1);node.geometry?.firstMaterial?.roughness.contents=0.9
            scene.rootNode.addChildNode(node)
        }
        let floor=SCNNode(geometry:SCNBox(width:80,height:0.2,length:80,chamferRadius:0));floor.position=SCNVector3(0,experiment.floor*100-0.1,0)
        floor.geometry?.firstMaterial?.diffuse.contents=NSColor.darkGray;scene.rootNode.addChildNode(floor)
        let cameraNode=SCNNode();cameraNode.name="camera";cameraNode.camera=SCNCamera();cameraNode.camera?.usesOrthographicProjection=true
        cameraNode.camera?.orthographicScale=camera == "Knot" ? 5:(experiment.kind == .strip ? 25:experiment.kind == .fold ? 10:experiment.kind == .wrap ? 23:30);cameraNode.camera?.zNear=0.1;cameraNode.camera?.zFar=300
        let center=camera == "Knot" ? SCNVector3(0,0.5,0):target(experiment.kind)
        cameraNode.position=camera == "Front" || camera == "Knot" ? SCNVector3(0,center.y,100):camera == "Side" ? SCNVector3(100,center.y,0):SCNVector3(52,center.y+36,70)
        cameraNode.look(at:center);scene.rootNode.addChildNode(cameraNode)
        for (type,intensity,position) in [(SCNLight.LightType.ambient,500.0,SCNVector3Zero),(.omni,1000.0,SCNVector3(-20,60,40)),(.omni,500.0,SCNVector3(30,10,-30))] {
            let node=SCNNode();node.light=SCNLight();node.light?.type=type;node.light?.intensity=intensity;node.position=position;scene.rootNode.addChildNode(node)
        }
        return scene
    }
}

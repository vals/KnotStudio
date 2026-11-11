import AppKit
import SceneKit
import SwiftUI
import simd

struct SceneSettings {
    var knot: KnotKind = .fourInHand
    var fabric = FabricSettings()
    var spread: Double = 0
    var showPath = false
    var selectedMove = -1
    var camera = "Portrait"
    var reset = 0
    var refined = true
    var premade = true
}

final class StudioSCNView: SCNView {
    override var acceptsFirstResponder: Bool { true }
}

struct RibbonScene: NSViewRepresentable {
    let settings: SceneSettings
    var controller: StudioViewController
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> StudioSCNView {
        let view = StudioSCNView(frame:.zero)
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = NSColor(srgbRed:0.075,green:0.095,blue:0.12,alpha:1)
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.autoenablesDefaultLighting = false
        context.coordinator.view = view
        controller.view = view
        return view
    }
    func updateNSView(_ view: StudioSCNView, context: Context) {
        let previousCamera = view.pointOfView?.presentation.transform
        let previousLens = view.pointOfView?.camera?.copy() as? SCNCamera
        let scene = SceneFactory.make(settings)
        view.scene = scene
        view.pointOfView = scene.rootNode.childNode(withName:"camera",recursively:false)
        if context.coordinator.camera == settings.camera && context.coordinator.reset == settings.reset && context.coordinator.knot == settings.knot, let old = previousCamera {
            view.pointOfView?.transform = old
            if let lens=previousLens { view.pointOfView?.camera=lens }
        }
        context.coordinator.camera = settings.camera; context.coordinator.reset = settings.reset; context.coordinator.knot=settings.knot
        view.defaultCameraController.target = SceneFactory.target(settings)
    }
    final class Coordinator {
        weak var view: StudioSCNView?
        var camera = "", reset = -1
        var knot:KnotKind?
    }
}

enum SceneFactory {
    static func make(_ settings: SceneSettings) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor(srgbRed:0.075,green:0.095,blue:0.12,alpha:1)
        let model = RibbonBuilder.build(settings.knot)
        let mesh = settings.premade && settings.knot == .fourInHand ? PremadeFourInHand.build(spread:settings.spread,flat:settings.camera == "Flat").mesh:RibbonMesh(model,spread:settings.spread,refined:settings.refined,flat:settings.camera == "Flat")
        let geometry = geometry(mesh,fabric:settings.fabric)
        let ribbon = SCNNode(geometry:geometry); ribbon.name = settings.premade && settings.knot == .fourInHand ? "authored-fabric-panels" : "continuous-fabric"; scene.rootNode.addChildNode(ribbon)
        if !(settings.premade && settings.knot == .fourInHand) && settings.showPath && settings.camera != "Flat" {
            for i in stride(from:0,to:model.samples.count-1,by:5) {
                let a = model.samples[i], b = model.samples[min(i+5,model.samples.count-1)]
                let color = a.phase < 0 ? NSColor.systemGray : NSColor(calibratedHue:Double(a.phase%8)/8,saturation:0.75,brightness:1,alpha:1)
                scene.rootNode.addChildNode(line(RibbonSurface.position(a,transverse:0,side:3,kind:settings.knot,spread:settings.spread,refined:settings.refined),RibbonSurface.position(b,transverse:0,side:3,kind:settings.knot,spread:settings.spread,refined:settings.refined),color:color))
            }
        }
        for crossing in model.crossings where !(settings.premade && settings.knot == .fourInHand) && settings.camera != "Flat" && (settings.showPath || settings.selectedMove == crossing.moveIndex) {
            var p = RibbonSurface.shape(crossing.anchor,kind:settings.knot,refined:settings.refined)
            p.z += settings.spread*(Double(crossing.moveIndex)*0.58-1.0)
            p.x *= 1+settings.spread*0.13
            let dot = SCNSphere(radius:settings.selectedMove == crossing.moveIndex ? 0.18 : 0.11)
            dot.firstMaterial?.diffuse.contents = NSColor.systemOrange
            dot.firstMaterial?.emission.contents = NSColor.systemOrange.withAlphaComponent(0.35)
            let marker = SCNNode(geometry:dot); marker.position = SCNVector3(p + V3(0,0,0.1)); scene.rootNode.addChildNode(marker)
            let label = SCNText(string:"\(crossing.moveIndex+1)  \(crossing.token)",extrusionDepth:0)
            label.font = NSFont.monospacedSystemFont(ofSize:0.34,weight:.medium); label.flatness = 0.05
            label.firstMaterial?.diffuse.contents = NSColor.white; label.firstMaterial?.emission.contents = NSColor.white
            let node = SCNNode(geometry:label); node.position = SCNVector3(p+V3(0.22,0.12,0.2)); node.constraints = [SCNBillboardConstraint()]; scene.rootNode.addChildNode(node)
        }
        let camera = SCNNode(); camera.name = "camera"; camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        let close = settings.camera == "Knot" || settings.camera == "Side"
        camera.camera?.orthographicScale = settings.camera == "Flat" ? 13 : (close ? (settings.premade && settings.knot == .fourInHand ? 4.7 : 4.2) : (settings.knot == .fourInHand ? 27.0 : 14.0))
        if settings.premade && settings.knot == .fourInHand {
            camera.camera?.screenSpaceAmbientOcclusionIntensity = 0.85
            camera.camera?.screenSpaceAmbientOcclusionRadius = 1.4
            camera.camera?.screenSpaceAmbientOcclusionBias = 0.035
        }
        camera.camera?.zNear = 0.1; camera.camera?.zFar = 150
        let target = target(settings)
        camera.position = settings.camera == "Side" ? SCNVector3(28,7,24) : SCNVector3(0,target.y,40)
        camera.look(at:target); scene.rootNode.addChildNode(camera)
        func light(_ type: SCNLight.LightType,_ intensity: CGFloat,_ position: SCNVector3,_ color: NSColor) {
            let node = SCNNode(); node.light = SCNLight(); node.light?.type = type; node.light?.intensity = intensity; node.light?.color = color
            node.position = position; node.look(at:SCNVector3(0,0,0)); scene.rootNode.addChildNode(node)
        }
        light(.ambient,280,SCNVector3Zero,.white)
        light(.omni,1050,SCNVector3(-8,10,15),NSColor(srgbRed:1,green:0.91,blue:0.8,alpha:1))
        light(.omni,320,SCNVector3(9,0,8),NSColor(srgbRed:0.72,green:0.84,blue:1,alpha:1))
        return scene
    }
    static func target(_ settings:SceneSettings)->SCNVector3 {
        if settings.premade && settings.knot == .fourInHand && settings.camera == "Flat" {return SCNVector3(0,13,0)}
        let model=RibbonBuilder.build(settings.knot)
        let close=settings.camera == "Knot" || settings.camera == "Side"
        return SCNVector3(0,settings.camera == "Flat" ? -model.length/2+13 : (close ? 0.5 : (settings.knot == .fourInHand ? -17.5 : -4.8)),0)
    }
    static func geometry(_ mesh:RibbonMesh,fabric:FabricSettings) -> SCNGeometry {
        let front=material(fabric),back=material(fabric,back:true)
        let edge=SCNMaterial();edge.diffuse.contents=fabric.base;edge.roughness.contents=0.85
        let texture = mesh.textureCoordinates(repeatCM:fabric.repeatCM,offsetCM:fabric.offsetCM,angle:fabric.angle * .pi / 180,aspect:fabric.aspect)
        let sources = [SCNGeometrySource(vertices:mesh.positions.map(SCNVector3.init)),SCNGeometrySource(normals:mesh.normals.map(SCNVector3.init)),SCNGeometrySource(textureCoordinates:texture.map{CGPoint(x:$0.x,y:$0.y)})]
        let elements = [mesh.front,mesh.back,mesh.edges].map { SCNGeometryElement(indices:$0,primitiveType:.triangles) }
        let geometry = SCNGeometry(sources:sources,elements:elements); geometry.materials = [front,back,edge]
        return geometry
    }
    static func material(_ fabric: FabricSettings,back: Bool = false) -> SCNMaterial {
        let result = SCNMaterial(); result.diffuse.contents = FabricTexture.make(fabric,back:back)
        result.diffuse.wrapS = .repeat; result.diffuse.wrapT = .repeat
        result.diffuse.magnificationFilter = .linear; result.diffuse.minificationFilter = .linear; result.diffuse.mipFilter = .linear
        result.lightingModel = .physicallyBased; result.roughness.contents = 0.72; result.metalness.contents = 0.0
        result.isDoubleSided = false
        return result
    }
    static func line(_ a: V3,_ b: V3,color: NSColor) -> SCNNode {
        let delta = b-a, length = simd_length(delta)
        let tube = SCNCylinder(radius:0.024,height:CGFloat(length)); tube.radialSegmentCount = 5
        tube.firstMaterial?.diffuse.contents = color; tube.firstMaterial?.emission.contents = color
        let node = SCNNode(geometry:tube); node.position = SCNVector3((a+b)/2)
        node.simdOrientation = simd_quatf(from:SIMD3<Float>(0,1,0),to:SIMD3<Float>(unit(delta)))
        return node
    }
}

extension SCNVector3 {
    init(_ v: V3) { self.init(CGFloat(v.x),CGFloat(v.y),CGFloat(v.z)) }
}

/// Captures the actual orbit and zoom rather than silently returning to a preset.
final class StudioViewController: ObservableObject {
    weak var view:StudioSCNView?
    func png() throws -> Data {
        guard let view=view,let scene=view.scene,let current=view.pointOfView,view.bounds.height>0 else { throw SnapshotError.noScene }
        let camera=SCNNode();camera.transform=current.presentation.transform
        camera.camera=current.camera?.copy() as? SCNCamera
        let renderer=SCNRenderer(device:nil,options:nil);renderer.scene=scene;renderer.pointOfView=camera
        let ratio=view.bounds.width/view.bounds.height
        let size=ratio>=1 ? NSSize(width:1800,height:1800/ratio) : NSSize(width:1800*ratio,height:1800)
        let image=renderer.snapshot(atTime:0,with:size,antialiasingMode:.multisampling4X)
        guard let data=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data),let png=bitmap.representation(using:.png,properties:[:]) else { throw SnapshotError.encoding }
        return png
    }
    enum SnapshotError:Error,LocalizedError {
        case noScene,encoding
        var errorDescription:String? { self == .noScene ? "The view is not ready to export. Try again once the model appears." : "The preview could not be encoded as a PNG." }
    }
}

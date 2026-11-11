import AppKit
import SceneKit
import simd

enum CameraPreset: String, CaseIterable, Identifiable {
    case knot = "Knot", portrait = "Portrait", side = "Side", back = "Back"
    var id: String { rawValue }
}

struct SimStats: Equatable {
    var stepMillis = 0.0
    var triangles = 0
    var moving = false
    var shownSteps = 0
    var freeLength = 0.0
    var narrowEnd = 0.0
}

/// Owns the SceneKit scene and the simulation. The simulation is stepped on
/// SceneKit's render thread; the UI hands over new goals and settings through
/// a small locked mailbox.
final class KnotSceneController: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let sim = KnotSim()
    let cameraNode = SCNNode()
    private let ribbon = SCNNode()
    private let frontMaterial = SCNMaterial()
    private let backMaterial = SCNMaterial()
    private var textureKey = ""
    private var lined = true
    private let collarNode = SCNNode()
    private let collarMaterial = SCNMaterial()
    private var collarKey = ""
    private var collarPositions: [Float] = [], collarNormals: [Float] = [], collarIndices: [UInt32] = []

    private let lock = NSLock()
    private var pendingGoal: KnotProgram?
    private var pendingFull: KnotProgram?
    /// Knot centre, wide tip and narrow tip heights, copied out for the camera.
    private var extents = (-1.6, -45.0, -42.0)
    private var pendingParams: KnotParams?
    private var lastTime: TimeInterval?
    private var idleFrames = 0
    private var idle = false
    private var smoothedMillis = 0.0
    /// Totals since launch, for the self-test: live frames stepped, step cost.
    private(set) var liveFrames = 0
    private(set) var liveMillisTotal = 0.0
    private(set) var liveMillisWorst = 0.0
    private(set) var liveSeconds = 0.0
    private var statsTick = 0
    var onStats: ((SimStats) -> Void)?
    /// Called on the main thread when the model starts or stops moving.
    var onActivity: ((Bool) -> Void)?

    private static let collarCategory = 2
    static let background = NSColor(srgbRed: 0.075, green: 0.095, blue: 0.12, alpha: 1)

    override init() {
        super.init()
        scene.background.contents = Self.background
        ribbon.name = "tie"
        scene.rootNode.addChildNode(ribbon)
        collarNode.name = "collar"
        scene.rootNode.addChildNode(collarNode)
        collarMaterial.lightingModel = .physicallyBased
        collarMaterial.diffuse.contents = NSColor(srgbRed: 0.90, green: 0.91, blue: 0.93, alpha: 1)
        collarMaterial.roughness.contents = 0.9
        collarMaterial.metalness.contents = 0.0
        collarMaterial.isDoubleSided = true
        // The collar has its own unshadowed key light: the shadow pass is tuned
        // for the tie's closely stacked layers and speckles on a broad surface.
        collarNode.castsShadow = false
        collarNode.categoryBitMask = Self.collarCategory

        for material in [frontMaterial, backMaterial] {
            material.lightingModel = .physicallyBased
            material.roughness.contents = 0.78
            material.metalness.contents = 0.0
            material.isDoubleSided = false
            material.diffuse.wrapS = .repeat; material.diffuse.wrapT = .repeat
            material.diffuse.minificationFilter = .linear; material.diffuse.magnificationFilter = .linear
            material.diffuse.mipFilter = .linear
            material.diffuse.maxAnisotropy = 8
        }

        cameraNode.name = "camera"
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.zNear = 0.1; camera.zFar = 400
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        func light(_ type: SCNLight.LightType, _ intensity: CGFloat, _ position: SCNVector3, _ color: NSColor) -> SCNNode {
            let node = SCNNode(); node.light = SCNLight()
            node.light?.type = type; node.light?.intensity = intensity; node.light?.color = color
            node.position = position; node.look(at: SCNVector3(0, -2, 0))
            scene.rootNode.addChildNode(node)
            return node
        }
        _ = light(.ambient, 330, SCNVector3Zero, .white)
        let key = light(.directional, 820, SCNVector3(-9, 14, 22), NSColor(srgbRed: 1, green: 0.94, blue: 0.86, alpha: 1))
        key.light?.castsShadow = true
        key.light?.shadowMode = .forward
        key.light?.shadowColor = NSColor.black.withAlphaComponent(0.42)
        key.light?.shadowRadius = 5
        key.light?.shadowSampleCount = 12
        key.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.light?.orthographicScale = 14
        key.light?.shadowBias = 9
        key.light?.zNear = 1; key.light?.zFar = 120
        key.light?.categoryBitMask = ~Self.collarCategory
        let plainKey = light(.directional, 820, SCNVector3(-9, 14, 22), NSColor(srgbRed: 1, green: 0.94, blue: 0.86, alpha: 1))
        plainKey.light?.categoryBitMask = Self.collarCategory
        _ = light(.omni, 260, SCNVector3(12, -2, 14), NSColor(srgbRed: 0.74, green: 0.85, blue: 1, alpha: 1))
        _ = light(.omni, 420, SCNVector3(-6, 6, -30), .white)

        apply(fabric: FabricSettings())
        place(.knot)
    }

    // MARK: From the UI (main thread)

    func set(goal: KnotProgram, full: KnotProgram? = nil) { lock.lock(); pendingGoal = goal; pendingFull = full ?? goal; idle = false; lock.unlock() }
    func set(params: KnotParams) { lock.lock(); pendingParams = params; idle = false; lock.unlock() }
    /// True once the model has come to rest and nothing new has been asked of it.
    var isIdle: Bool { lock.lock(); defer { lock.unlock() }; return idle }

    func apply(fabric: FabricSettings) {
        if fabric.textureKey != textureKey {
            textureKey = fabric.textureKey
            frontMaterial.diffuse.contents = FabricTexture.make(fabric)
            // The back shows the tie's lining, mapped along its whole length;
            // the diagnostic displays use the same chart on both faces.
            lined = fabric.display == .fabric
            backMaterial.diffuse.contents = lined ? FabricTexture.lining(fabric) : FabricTexture.make(fabric, back: true)
            backMaterial.diffuse.mappingChannel = lined ? 1 : 0
            backMaterial.diffuse.wrapS = lined ? .clamp : .repeat
            backMaterial.diffuse.wrapT = lined ? .clamp : .repeat
            let weave = FabricTexture.weaveNormal(fabric.cloth)
            let tile = CGFloat(1 / fabric.cloth.weaveTile)
            for material in [frontMaterial, backMaterial] {
                material.normal.contents = fabric.display == .fabric ? weave : nil
                material.normal.wrapS = .repeat; material.normal.wrapT = .repeat
                material.normal.mipFilter = .linear
                material.normal.maxAnisotropy = 8
                material.normal.intensity = 1
                material.normal.contentsTransform = SCNMatrix4MakeScale(tile, tile, 1)
                material.roughness.contents = fabric.display == .fabric ? fabric.cloth.roughness : 0.8
            }
        }
        let transform = fabric.chartTransform
        frontMaterial.diffuse.contentsTransform = transform
        backMaterial.diffuse.contentsTransform = lined ? SCNMatrix4Identity : transform
    }

    var showCollar = true { didSet { collarNode.isHidden = !showCollar } }

    func place(_ preset: CameraPreset) {
        lock.lock(); let (yc, wideTipY, narrowTipY) = extents; lock.unlock()
        let camera = cameraNode.camera!
        switch preset {
        case .knot:
            cameraNode.position = SCNVector3(0, yc - 0.6, 60)
            cameraNode.eulerAngles = SCNVector3Zero
            camera.orthographicScale = 7.6
        case .portrait:
            let low = min(wideTipY, narrowTipY), high = 9.0
            let mid = (low + high) / 2
            cameraNode.position = SCNVector3(0, mid, 60)
            cameraNode.eulerAngles = SCNVector3Zero
            camera.orthographicScale = (high - low) / 2 + 2
        case .side:
            cameraNode.position = SCNVector3(34, yc + 9, 44)
            cameraNode.look(at: SCNVector3(0, yc - 0.6, 0))
            camera.orthographicScale = 8.2
        case .back:
            cameraNode.position = SCNVector3(0, yc - 0.6, -60)
            cameraNode.eulerAngles = SCNVector3(0, CGFloat.pi, 0)
            camera.orthographicScale = 7.6
        }
    }
    var orbitTarget: SCNVector3 { lock.lock(); defer { lock.unlock() }; return SCNVector3(0, extents.0 - 0.6, 0) }

    // MARK: Simulation

    private func takeMail() {
        lock.lock()
        if let goal = pendingGoal { sim.goal = goal; sim.fullProgram = pendingFull; pendingGoal = nil }
        if let params = pendingParams { sim.params = params; pendingParams = nil }
        lock.unlock()
    }

    /// Advance the model and refresh the geometry. Returns the step cost in ms.
    @discardableResult
    func advance(_ dt: Double) -> Double {
        takeMail()
        let start = DispatchTime.now().uptimeNanoseconds
        sim.step(dt)
        let millis = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        ribbon.geometry = makeGeometry()
        refreshCollar()
        publishExtents()
        return millis
    }

    /// For offscreen use: jump to the goal, let it rest, refresh the geometry.
    func settle(seconds: Double = 3) {
        takeMail()
        sim.settle(seconds: seconds)
        ribbon.geometry = makeGeometry()
        refreshCollar()
        publishExtents()
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) { tick(time) }

    /// One frame of the live loop. SceneKit calls this before each redraw.
    func tick(_ time: TimeInterval) {
        let dt = lastTime.map { min(max(time - $0, 0), 0.1) } ?? 1.0 / 60
        lastTime = time
        lock.lock(); let mail = pendingGoal != nil || pendingParams != nil; lock.unlock()
        if !sim.isMoving && !mail {
            idleFrames += 1
            if idleFrames == 20 {
                lock.lock(); idle = pendingGoal == nil && pendingParams == nil; lock.unlock()
                report(moving: false)
            }
            return
        }
        if idleFrames >= 20 { DispatchQueue.main.async { self.onActivity?(true) } }
        idleFrames = 0
        let millis = advance(dt)
        liveFrames += 1; liveMillisTotal += millis; liveMillisWorst = max(liveMillisWorst, millis); liveSeconds += dt
        smoothedMillis = smoothedMillis == 0 ? millis : smoothedMillis * 0.9 + millis * 0.1
        statsTick += 1
        if statsTick % 12 == 0 { report(moving: true) }
    }

    private func publishExtents() {
        lock.lock(); extents = (sim.knotCenterY, sim.wideTipY, sim.narrowTipY); lock.unlock()
    }

    private func report(moving: Bool) {
        let stats = SimStats(stepMillis: smoothedMillis, triangles: sim.mesh.triangleCount, moving: moving,
                             shownSteps: sim.shown.stepCount, freeLength: sim.freeLength, narrowEnd: sim.narrowEnd)
        DispatchQueue.main.async {
            self.onStats?(stats)
            if !moving { self.onActivity?(false) }
        }
    }

    private func makeGeometry() -> SCNGeometry {
        let mesh = sim.mesh
        func data<T>(_ array: [T]) -> Data { array.withUnsafeBufferPointer { Data(buffer: $0) } }
        let count = mesh.vertexCount
        let sources = [
            SCNGeometrySource(data: data(mesh.positions), semantic: .vertex, vectorCount: count, usesFloatComponents: true,
                              componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
            SCNGeometrySource(data: data(mesh.normals), semantic: .normal, vectorCount: count, usesFloatComponents: true,
                              componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
            SCNGeometrySource(data: data(mesh.chart), semantic: .texcoord, vectorCount: count, usesFloatComponents: true,
                              componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8),
            SCNGeometrySource(data: data(mesh.liningChart), semantic: .texcoord, vectorCount: count, usesFloatComponents: true,
                              componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8),
        ]
        let elements = [mesh.front, mesh.back].map {
            SCNGeometryElement(data: data($0), primitiveType: .triangles, primitiveCount: $0.count / 3, bytesPerIndex: 4)
        }
        let geometry = SCNGeometry(sources: sources, elements: elements)
        geometry.materials = [frontMaterial, backMaterial]
        return geometry
    }

    /// The collar only changes while the knot is being dressed or undressed.
    private func refreshCollar() {
        let key = String(format: "%.3f|%.3f|%.3f", sim.neck.yFront, sim.neck.zc, sim.collarFold)
        guard key != collarKey else { return }
        collarKey = key
        Collar.build(neck: sim.neck, fold: sim.collarFold, positions: &collarPositions, normals: &collarNormals, indices: &collarIndices)
        func data<T>(_ array: [T]) -> Data { array.withUnsafeBufferPointer { Data(buffer: $0) } }
        let count = collarPositions.count / 3
        let geometry = SCNGeometry(sources: [
            SCNGeometrySource(data: data(collarPositions), semantic: .vertex, vectorCount: count, usesFloatComponents: true,
                              componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
            SCNGeometrySource(data: data(collarNormals), semantic: .normal, vectorCount: count, usesFloatComponents: true,
                              componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
        ], elements: [SCNGeometryElement(data: data(collarIndices), primitiveType: .triangles, primitiveCount: collarIndices.count / 3, bytesPerIndex: 4)])
        geometry.materials = [collarMaterial]
        collarNode.geometry = geometry
    }

    // MARK: Snapshots

    func snapshot(size: NSSize, pointOfView: SCNNode? = nil) -> NSImage {
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = pointOfView ?? cameraNode
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }

    static func png(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

import Foundation

/// A display choice, independent of the user's persistent swatch and placement.
enum FabricViewMode:String,CaseIterable,Identifiable {
    case fabric = "Fabric", uvGrid = "UV grid", faceIdentity = "Face identity"
    var id:String { rawValue }
}
struct FabricViewState {
    var mode:FabricViewMode = .fabric
    func displayedFabric(from fabric:FabricSettings)->FabricSettings {
        guard mode != .fabric else { return fabric }
        var display=fabric
        display.pattern = mode == .uvGrid ? .ruler : .faces
        display.angle=0;display.offsetCM=0;display.repeatCM=4
        return display
    }
}

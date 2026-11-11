import Foundation
import AppKit

@main
struct ViewStateChecks {
    static func main() {
        var checks=0
        func check(_ condition:Bool,_ message:String) { checks+=1;if !condition { fputs("FAIL: \(message)\n",stderr);exit(1) } }
        let swatch=NSImage(size:NSSize(width:512,height:256))
        var fabric=FabricSettings(pattern:.imported,base:.purple,accent:.orange,repeatCM:5.3,offsetCM:7.2,angle:37,image:swatch)
        var state=FabricViewState()
        let transitions:[FabricViewMode]=[.uvGrid,.faceIdentity,.fabric,.faceIdentity,.uvGrid,.fabric,.fabric]
        for _ in 0..<5 { for mode in transitions {
            state.mode=mode
            let displayed=state.displayedFabric(from:fabric)
            check(fabric.pattern == .imported && fabric.image === swatch,"diagnostics preserve imported image identity and selected pattern")
            check(fabric.repeatCM == 5.3 && fabric.offsetCM == 7.2 && fabric.angle == 37,"diagnostics preserve repeat, offset and angle")
            check(displayed.base == .purple && displayed.accent == .orange,"colors preserved")
            if mode == .fabric {
                check(displayed.pattern == .imported && displayed.image === swatch,"Fabric restores the original swatch")
                check(displayed.repeatCM == 5.3 && displayed.offsetCM == 7.2 && displayed.angle == 37,"Fabric restores original placement")
            } else {
                check(displayed.pattern == (mode == .uvGrid ? .ruler:.faces),"requested diagnostic appears")
                check(displayed.angle == 0 && displayed.offsetCM == 0 && displayed.repeatCM == 4,"diagnostic has its own chart placement")
            }
        }}
        state.mode = .uvGrid;fabric.angle = -21;fabric.repeatCM = 2.8;fabric.offsetCM=1.4
        state.mode = .fabric
        let edited=state.displayedFabric(from:fabric)
        check(edited.angle == -21 && edited.repeatCM == 2.8 && edited.offsetCM == 1.4 && edited.image === swatch,"edits made during diagnostics survive returning to Fabric")
        for pattern in [FabricPattern.stripes,.dots,.check,.solid] {
            fabric.pattern=pattern
            for mode in transitions { state.mode=mode;_ = state.displayedFabric(from:fabric) }
            check(state.displayedFabric(from:fabric).pattern == pattern,"built-in pattern restored")
        }
        print("PASS: \(checks) display-mode transition checks; imported image and placement preserved")
    }
}

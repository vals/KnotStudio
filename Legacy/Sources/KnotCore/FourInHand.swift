import Foundation
import simd

/// A single continuous strip following Li Ro Li Co T (Denne et al., Fig. 5–6).
/// The front is the third move itself, not a separate knot shell. Dimensions and
/// local ribbon widths are authored; this is not a cloth/contact solution.
enum FourInHand {
    private struct Key {
        var p: V3
        var guide: V3
        var width: Double
        var phase: Int
    }

    static func build(frameCorrection:Double = 0.3) -> RibbonModel {
        var keys: [Key] = []
        func key(_ p: V3, _ guide: V3, _ width: Double, _ phase: Int = -1) {
            keys.append(Key(p:p,guide:unit(guide),width:width,phase:phase))
        }
        // Passive tail, then neck loop. The two ends remain part of one strip.
        key(V3(0,-34,-0.32),V3(1,0,0),0.04)
        key(V3(0,-32.5,-0.32),V3(1,0,0),3.1)
        key(V3(0,-18,-0.32),V3(1,0,0),2.7)
        key(V3(0,-5,-0.32),V3(1,0,0),1.6)
        key(V3(0,-0.5,-0.25),V3(1,0,0),1.1)
        key(V3(0,1.15,-0.25),V3(1,0,0),1.0)
        key(V3(-1.30,2.4,-0.28),V3(0.8,0.6,0),1.15)
        key(V3(-2.1,3.3,-0.45),V3(0.8,0.6,0),1.65)
        key(V3(-3.4,5.0,-1.8),V3(0.4,0.9,0),1.8)
        key(V3(-3.6,5.7,-4.4),V3(0,1,0),1.8)
        key(V3(0,6.0,-6),V3(0,1,0),1.8)
        key(V3(3.6,5.7,-4.4),V3(-0.2,1,0),1.8)
        key(V3(3.4,4.9,-1.8),V3(-0.65,0.75,0),1.85)
        key(V3(2.1,2.9,-0.12),V3(-0.8,0.6,0),1.9)
        // Li is the diagonal continuation of the active neck strand, not a
        // small-radius turn from a vertical sheet into a horizontal ring.
        key(V3(1.0,2.30,0.0),V3(-0.7,0.7,0.0),1.0,0)
        key(V3(0.65,1.50,0.10),V3(-0.7,0.7,0.0),1.2,0)
        key(V3(-0.15,0.85,0.16),V3(-0.45,0.9,0.0),1.8,0)
        key(V3(-0.78,0.30,0.17),V3(-0.25,1,0.0),2.08,0)
        // Ro passes behind the passive strand; Li forms the final front wrap.
        for i in 0...64 {
            let theta = Double.pi + Double(i) / 64 * 2 * Double.pi
            let f = Double(i)/64
            let phase = i < 32 ? 1 : 2
            let radius = 1.04 + 0.19*f
            let depth = 0.67 + 0.22*f
            let y = 0.60 - 0.08*f + 0.10*cos(theta)
            let p = V3(radius*cos(theta)-0.07*f,y,0.02+depth*sin(theta))
            let guide = V3(0.30*cos(theta),1,0.025*sin(theta))
            key(p,guide,2.20+0.65*f,phase)
        }

        // Co: leave L, rise behind the left neck strand into its opening.
        key(V3(-1.29,0.25,-0.48),V3(-0.5,0.85,-0.1),1.65,3)
        key(V3(-0.98,0.95,-0.95),V3(-0.9,0.3,0.0),1.35,3)
        key(V3(-0.20,2.10,-0.70),V3(-1,0.0,0),0.95,3)
        // T: fold over the neck opening, then descend inside the front wrap.
        key(V3(0.02,2.45,-0.05),V3(-1,0,0),0.7,4)
        key(V3(0.12,2.02,0.38),V3(-1,0,0),1.1,4)
        key(V3(0.01,1.2,0.38),V3(-1,0,0),1.3,4)
        key(V3(-0.02,0.35,0.38),V3(-1,0,0),1.2,4)
        key(V3(-0.05,-0.85,0.38),V3(-1,0,0),1.2,4)
        key(V3(-0.05,-1.7,0.40),V3(-1,0,0),1.9,4)
        key(V3(-0.03,-3.4,0.35),V3(-1,0,0),2.5,4)
        key(V3(0,-10,0.2),V3(-1,0,0),3.6,4)
        key(V3(0,-25,0.05),V3(-1,0,0),5.4,4)
        key(V3(0,-39,0),V3(-1,0,0),7.1,4)
        key(V3(0,-42.7,0),V3(-1,0,0),0.035,4)

        var raw: [Key] = []
        func boundedHermite(_ a:V3,_ b:V3,_ c:V3,_ d:V3,_ t:Double)->V3 {
            let t2=t*t, t3=t2*t
            let length=simd_distance(b,c)
            let left=unit(c-a)*min(length,simd_distance(a,b))
            let right=unit(d-b)*min(length,simd_distance(c,d))
            var result=V3.zero
            for axis in 0..<3 {
                result[axis]=(2*t3-3*t2+1)*b[axis]+(t3-2*t2+t)*left[axis]+(-2*t3+3*t2)*c[axis]+(t3-t2)*right[axis]
            }
            return result
        }
        for i in 0..<(keys.count-1) {
            let a=keys[max(0,i-1)],b=keys[i],c=keys[i+1],d=keys[min(keys.count-1,i+2)]
            let count=max(5,Int(simd_distance(b.p,c.p)*20))
            for j in 0..<count {
                let t=Double(j)/Double(count), ease=t*t*(3-2*t)
                raw.append(Key(p:boundedHermite(a.p,b.p,c.p,d.p,t),guide:unit(b.guide*(1-ease)+c.guide*ease),width:b.width+(c.width-b.width)*ease,phase:c.phase))
            }
        }
        raw.append(keys.last!)
        var samples:[RibbonSample]=[], s=0.0
        for i in raw.indices {
            if i>0 { s += simd_distance(raw[i].p,raw[i-1].p) }
            let tangent=unit(raw[min(i+1,raw.count-1)].p-raw[max(0,i-1)].p)
            // Reduce alignment between the authored fold guide and the route.
            // Full projection can fold a wide ruled surface through itself.
            // This bounded correction reduces skew; metric/contact are audited
            // on the emitted mesh, and this is not an isometric cloth solve.
            let guide=raw[i].guide
            // Retain oblique rulings near the left wrap joins: projecting those
            // would make neighboring rows cross. Taper continuously away.
            let correction=frameCorrection*RibbonSurface.smooth(-0.75,0.10,raw[i].p.x)
            let across=unit(guide-tangent*simd_dot(guide,tangent)*correction)
            samples.append(RibbonSample(center:raw[i].p,across:across,normal:unit(simd_cross(across,tangent)),width:raw[i].width,s:s,phase:raw[i].phase))
        }
        let targets=[V3(0,0.4,0.5),V3(0,0.3,-0.55),V3(0,0.2,0.75),V3(-0.6,1.7,-0.7)]
        // Keep the assumed flat blank independent of all visual shape changes.
        // Narrow spatial cross-sections compress the full material domain; they
        // no longer silently delete transverse artwork from the ribbon chart.
        let referenceLength=samples.last!.s
        for i in samples.indices {
            samples[i].routeS=samples[i].s
            samples[i].s=samples[i].s/referenceLength*TieBlank.lengthCM
            samples[i].materialWidth=TieBlank.width(at:samples[i].s)
        }
        let crossings=KnotKind.fourInHand.sequence.moves.enumerated().map { i,move in
            let sample=samples.filter{$0.phase==i}.min{simd_distance($0.center,targets[i])<simd_distance($1.center,targets[i])}!
            return Crossing(token:move.token,anchor:sample.center,moveIndex:i)
        }
        return RibbonModel(kind:.fourInHand,samples:samples,crossings:crossings)
    }
}

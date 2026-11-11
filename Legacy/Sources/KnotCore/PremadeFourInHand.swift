import Foundation
import simd

/// A reference-shaped visual preset. Separate surface panels approximate hidden
/// assembly; this is not the solver seed or an arbitrary sequence renderer.
enum PremadeFourInHand {
    struct Part {let name:String,first:Int,count:Int,rows:Int,columns:Int}
    struct Model {let mesh:RibbonMesh,parts:[Part]}
    static func smooth(_ a:Double,_ b:Double,_ x:Double)->Double {RibbonSurface.smooth(a,b,x)}
    static func build(spread:Double=0,flat:Bool=false)->Model {
        var positions:[V3]=[],normals:[V3]=[],chart:[SIMD2<Double>]=[]
        var front:[Int32]=[],back:[Int32]=[],edges:[Int32]=[],parts:[Part]=[]
        func patch(_ name:String,_ rows:Int,_ columns:Int,_ shift:Double=0,_ point:(Double,Double)->(V3,SIMD2<Double>)) {
            let start=positions.count,n=rows*columns
            var p:[V3]=[],uv:[SIMD2<Double>]=[]
            for i in 0..<rows {for j in 0..<columns {
                let (v,t)=point(Double(i)/Double(rows-1),Double(j)/Double(columns-1))
                p.append(v+V3(0,0,shift*spread));uv.append(t)
            }}
            var ns=[V3](repeating:.zero,count:n)
            for i in 0..<rows {for j in 0..<columns {
                let left=p[i*columns+max(0,j-1)],right=p[i*columns+min(columns-1,j+1)]
                let previous=p[max(0,i-1)*columns+j],next=p[min(rows-1,i+1)*columns+j]
                ns[i*columns+j]=unit(simd_cross(right-left,next-previous))
            }}
            for side in [1.0,-1.0] {
                positions += p.indices.map{p[$0]+ns[$0]*(0.018*side)}
                normals += ns.map{$0*side};chart+=uv
            }
            for i in 0..<rows-1 {for j in 0..<columns-1 {
                let a=Int32(start+i*columns+j),b=a+1,c=a+Int32(columns),d=c+1,o=Int32(n)
                front += [a,b,c,b,d,c];back += [a+o,c+o,b+o,b+o,c+o,d+o]
            }}
            for i in 0..<rows-1 {for j in [0,columns-1] {
                let a=Int32(start+i*columns+j),b=a+Int32(columns),c=a+Int32(n),d=b+Int32(n)
                edges += j==0 ? [a,b,c,b,d,c]:[a,c,b,b,c,d]
            }}
            for i in [0,rows-1] {for j in 0..<columns-1 {
                let a=Int32(start+i*columns+j),b=a+1,c=a+Int32(n),d=b+Int32(n)
                edges += i==0 ? [a,c,b,b,c,d]:[a,b,c,b,d,c]
            }}
            parts.append(Part(name:name,first:start,count:n,rows:rows,columns:columns))
        }
        // A slightly leaning, developed cone supplies the material chart. The
        // visible surface softens that cone at its belly and turns the crown in.
        // Local softening is deliberately small; the chart is never normalized
        // to [0,1] at a narrowing row or projected from the viewing camera.
        let angularSteps=4096,dt=2*Double.pi/Double(4096)
        func generator(_ theta:Double)->V3 {V3(0.07+0.24*sin(theta),1,0.15*cos(theta))}
        var phi=[Double](repeating:0,count:angularSteps+1)
        for i in 1...angularSteps {
            let a=unit(generator(-Double.pi+Double(i-1)*dt))
            let b=unit(generator(-Double.pi+Double(i)*dt))
            phi[i]=phi[i-1]+acos(max(-1,min(1,simd_dot(a,b))))
        }
        func angle(_ theta:Double)->Double {
            let f=(theta+Double.pi)/dt,i=min(angularSteps-1,max(0,Int(f))),t=f-Double(i)
            return phi[i]*(1-t)+phi[i+1]*t-phi[angularSteps/2]
        }
        func wrap(_ theta:Double,_ t:Double)->(V3,SIMD2<Double>) {
            let pinch=0.085*exp(-pow((theta+0.12)/0.26,2))
            let bottom = -1.20+0.13*sin(theta)-0.035*cos(theta)+pinch
            let top=1.92+0.42*sin(theta)+0.14*cos(theta)
            let lowerRadius=0.060,upperRadius=0.095
            let body=min(1,max(0,(t-0.07)/0.85))
            var y=bottom+lowerRadius+(top-bottom-lowerRadius-upperRadius)*body
            var materialY=y,turn=0.0
            // The last rows curl back into the assembly. The visible silhouette
            // lies inside each turn, so neither border is a straight cut edge.
            if t<0.07 {
                let a=Double.pi*(1-t/0.07)
                y=bottom+lowerRadius-lowerRadius*sin(a)
                materialY=bottom+lowerRadius-lowerRadius*a
                turn=lowerRadius*(1-cos(a))
            } else if t>0.92 {
                let a=Double.pi*0.85*(t-0.92)/0.08
                y=top-upperRadius+upperRadius*sin(a)
                materialY=top-upperRadius+upperRadius*a
                turn=upperRadius*(1-cos(a))
            }
            let g=generator(theta),rho=(materialY+5.2)*simd_length(g)
            var p=V3(-0.5,-5.2,0)+g*(y+5.2)
            let belly=0.060*sin(Double.pi*body)
            let compression=exp(-pow((t-0.12)/0.19,2))*exp(-pow(theta/1.05,4))
            let smallFold=0.035*sin(4*theta+0.4)+0.010*sin(8*theta-0.7)
            p.x+=(0.045*sin(Double.pi*body)-turn)*sin(theta)
            p.z+=(belly-turn+smallFold*compression)*cos(theta)
            let a=angle(theta)
            return (p,SIMD2(rho*cos(a)-5.7,91-rho*sin(a)))
        }
        if !flat {
            patch("front wrap",193,97,0.65) {row,column in
                wrap(Double.pi-row*2*Double.pi,column)
            }
            // An inset turnover closes the crown within the rolled silhouette.
            // It approximates the hidden tuck; no separate tab crosses the front.
            patch("concealed crown",193,33,-0.15) {row,column in
                let theta = -Double.pi+row*2*Double.pi,r=0.002+column*0.986
                let (rim,uv)=wrap(theta,1),center=V3(0,1.76,0)
                var p=center+(rim-center)*r
                p.y-=0.045+0.055*sin(Double.pi*r)
                return (p,SIMD2(uv.x*r,96+(uv.y-91)*r))
            }
        }
        // Cross-fiber arc length is the parameter u. A smooth M section stores
        // width in the dimple instead of shrinking a full texture onto each row.
        patch("blade",301,65,0.1) {row,column in
            let distance=row*44.5,y=0.5-distance
            let width:Double
            if distance<40.8 {width=3.0+4.1*pow(distance/40.8,0.83)}
            else {width=max(0.035,7.1*(44.5-distance)/3.7)}
            let u=(column-0.5)*width
            let fold=1.63*(1-smooth(1.3,4.6,distance))
            let steps=80,du=u/Double(80)
            var x=0.0,z=0.0
            for k in 0..<steps {
                let t=(Double(k)+0.5)*du,beta=fold*sin(4*Double.pi*t/width)*(1+0.10*t/(width/2))
                x-=cos(beta)*du;z+=sin(beta)*du
            }
            let centerX = -0.20*exp(-distance/8)
            let centerZ = -0.22+0.36*smooth(1.5,4.6,distance)-0.12*smooth(12,42,distance)
            let p=flat ? V3(-u,44.5-distance,0):V3(x+centerX,y,centerZ+z)
            return (p,SIMD2(u,100+distance))
        }
        if !flat {
            for side in [-1.0,1.0] {
                patch(side<0 ? "left neck entry":"right neck entry",145,25,-0.7) {row,column in
                    let t = -2.0+3.0*row,u=(column-0.5)*1.65
                    let center=V3(side*(2.65-1.90*t),4.8-3.25*t,-1.4+0.76*t)
                    let tangent=unit(V3(-side*1.9,-3.25,0.76)),across=unit(simd_cross(tangent,V3(0,0,1)))
                    let fold:Double=1.25*smooth(0.35,1,t)
                    let du:Double=u/40.0
                    var transverse=0.0,depth=0.0
                    for k in 0..<40 {
                        let sample:Double=(Double(k)+0.5)*du
                        let phase:Double=2.0*Double.pi*sample/1.65
                        let a:Double=fold*sin(phase)
                        transverse+=cos(a)*du;depth+=sin(a)*du
                    }
                    let p=center+across*transverse+V3(0,0,depth)
                    return (p,SIMD2(u,(side<0 ? 43.0:76.0)+t*3.84))
                }
            }
            patch("passive tail",151,25,-1.1) {row,column in
                let d=row*34,width=d<32.3 ? 1.15+1.65*d/32.3:max(0.04,2.8*(34-d)/1.7),u=(column-0.5)*width
                return (V3(u-0.18,0.6-d,-0.30),SIMD2(u,34-d))
            }
        }
        return Model(mesh:RibbonMesh(positions:positions,normals:normals,chart:chart,front:front,back:back,edges:edges),parts:parts)
    }
}

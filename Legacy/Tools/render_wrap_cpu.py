"""Rasterize saved solver triangles with a CPU z-buffer; no app or graphics server.

This is geometry rendering, not a simulation or an app screenshot. Pillow/NumPy
must already be available. No source positions are altered for presentation.
"""
import json, math, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

directory=Path(sys.argv[1] if len(sys.argv)>1 else 'artifacts/cloth-0.7')
W,H=1200,900
eye=np.array([1.,.65,1.9]);eye/=np.linalg.norm(eye)
right=np.cross([0,1,0],eye);right/=np.linalg.norm(right)
up=np.cross(eye,right)
center=np.array([.01,.16,.065]);scale=2450.
light=np.array([-.3,1.,1.5]);light/=np.linalg.norm(light)

def render(frame):
    data=json.loads((directory/f'wrap-{frame}.json').read_text())
    positions=np.array(data['positions_m']);triangles=np.array(data['triangles'])
    rgb=np.zeros((H,W,3),dtype=np.uint8);rgb[:]=[22,29,37]
    depth=np.full((H,W),-np.inf)
    def triangle(points,color,two_sided=False):
        normal=np.cross(points[1]-points[0],points[2]-points[0]);length=np.linalg.norm(normal)
        if length<1e-15:return
        normal/=length
        if two_sided:
            color=np.array([51,171,170]) if normal@eye>=0 else np.array([195,105,70])
        if normal@eye<0:normal=-normal
        shade=.35+.65*max(0,normal@light)
        color=np.clip(np.array(color)*shade,0,255).astype(np.uint8)
        rel=points-center
        screen=np.stack([W/2+scale*(rel@right),H/2-scale*(rel@up)],axis=1)
        zs=rel@eye
        xmin=max(0,int(np.floor(screen[:,0].min())));xmax=min(W-1,int(np.ceil(screen[:,0].max())))
        ymin=max(62,int(np.floor(screen[:,1].min())));ymax=min(H-66,int(np.ceil(screen[:,1].max())))
        if xmax<xmin or ymax<ymin:return
        a,b,c=screen;den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
        if abs(den)<1e-12:return
        y,x=np.mgrid[ymin:ymax+1,xmin:xmax+1];x=x+.5;y=y+.5
        u=((b[1]-c[1])*(x-c[0])+(c[0]-b[0])*(y-c[1]))/den
        v=((c[1]-a[1])*(x-c[0])+(a[0]-c[0])*(y-c[1]))/den
        w=1-u-v;z=u*zs[0]+v*zs[1]+w*zs[2]
        patch=depth[ymin:ymax+1,xmin:xmax+1]
        mask=(u>=0)&(v>=0)&(w>=0)&(z>patch)
        patch[mask]=z[mask];rgb[ymin:ymax+1,xmin:xmax+1][mask]=color
    # The exact benchmark capsule: 35 mm radius, axis x=-100..100 mm.
    rings=[]
    for a in np.linspace(-math.pi/2,0,13):rings.append((-.1+.035*math.sin(a),.035*math.cos(a)))
    for a in np.linspace(0,math.pi/2,13):rings.append((.1+.035*math.sin(a),.035*math.cos(a)))
    vertices=np.array([[x,.16+r*math.cos(a),r*math.sin(a)] for x,r in rings for a in np.linspace(0,2*math.pi,97)[:-1]])
    for row in range(len(rings)-1):
        for j in range(96):
            a=row*96+j;b=row*96+(j+1)%96;c=a+96;d=b+96
            triangle(vertices[[a,b,c]],[105,117,128]);triangle(vertices[[b,d,c]],[105,117,128])
    for ids in triangles:triangle(positions[ids],[51,171,170],True)
    # Screen annotations describe evidence only; they do not obscure geometry.
    im=Image.fromarray(rgb);draw=ImageDraw.Draw(im)
    draw.text((30,22),f"KnotStudio 0.7 | {data['metrics']['phase']} | t = {data['time']:.3f} s",fill=(238,243,245))
    draw.text((30,H-49),"Saved solver mid-surface | teal / rust: opposite faces | gray: rounded support",fill=(210,222,229))
    draw.text((30,H-29),"CPU geometry render; not an app screenshot. Finite triangle/support contact enabled; see verification report for numerical tolerance.",fill=(175,191,203))
    target=directory/f'wrap-{frame}-cpu.png';im.save(target)
    print(target)

for frame in [0,135,255,315,330]:render(frame)

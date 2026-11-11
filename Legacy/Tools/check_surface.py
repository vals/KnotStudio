"""Check sampled ribbon mid-surface triangle intersections (not cloth contact).

Uses only NumPy. Shared and immediately neighbouring rows are excluded. A zero
count is a finite-mesh regression check, not a proof for a smooth thick cloth.
"""
import json
import sys
from itertools import product, combinations
from pathlib import Path
import numpy as np

rows=np.array(json.loads(Path(sys.argv[1]).read_text()))
# Retain full knot sampling; tails and distant neck cannot affect knot contact.
triangles=[]; row_ids=[]; phases=[]
across_count=12
u=np.linspace(-.5,.5,across_count+1)
vertices=rows[:,None,:3]+rows[:,None,3:6]*(rows[:,None,9:10]*u[None,:,None])
curve=.035*(1-(u*2)**2)
vertices+=rows[:,None,6:9]*curve[None,:,None]
thick='--thick' in sys.argv
for offset in ([.025,-.025] if thick else [0]):
    face=vertices+rows[:,None,6:9]*offset
    for i in range(len(rows)-1):
        if max(rows[i,1],rows[i+1,1]) < -3 or min(rows[i,1],rows[i+1,1]) > 3.5: continue
        for j in range(across_count):
            a,b,c,d=face[i,j],face[i,j+1],face[i+1,j],face[i+1,j+1]
            triangles.extend([[a,b,c],[b,d,c]]); row_ids.extend([i,i]); phases.extend([int(rows[i,11])]*2)
triangles=np.array(triangles); row_ids=np.array(row_ids)
lo=triangles.min(axis=1); hi=triangles.max(axis=1)
grid={}; size=.28
for i,(a,b) in enumerate(zip(np.floor(lo/size).astype(int),np.floor(hi/size).astype(int))):
    for cell in product(*(range(a[k],b[k]+1) for k in range(3))): grid.setdefault(cell,[]).append(i)
pairs=set()
for ids in grid.values():
    for i,j in combinations(ids,2):
        if abs(row_ids[i]-row_ids[j])>2 and np.all(hi[i]>=lo[j]) and np.all(hi[j]>=lo[i]): pairs.add((min(i,j),max(i,j)))
pairs=np.array(sorted(pairs),dtype=int).reshape(-1,2)
def hit(a,b):
    e1=b[:,1]-b[:,0];e2=b[:,2]-b[:,0]
    hits=np.zeros(len(a),dtype=bool)
    for k in range(3):
        origin=a[:,k];direction=a[:,(k+1)%3]-origin
        h=np.cross(direction,e2);det=np.einsum('ij,ij->i',e1,h)
        valid=np.abs(det)>1e-10
        inv=np.divide(1,det,out=np.zeros_like(det),where=valid)
        s=origin-b[:,0];u=inv*np.einsum('ij,ij->i',s,h)
        q=np.cross(s,e1);v=inv*np.einsum('ij,ij->i',direction,q)
        t=inv*np.einsum('ij,ij->i',e2,q)
        hits|=valid&(u>=-1e-8)&(v>=-1e-8)&(u+v<=1+1e-8)&(t>1e-7)&(t<1-1e-7)
    return hits
found=[]
if len(pairs):
    a=triangles[pairs[:,0]];b=triangles[pairs[:,1]]
    found=pairs[hit(a,b)|hit(b,a)]
groups={}
for a,b in found:
    key=f'{phases[a]}:{phases[b]}'
    groups[key]=groups.get(key,0)+1
report={'triangles':len(triangles),'candidate_pairs':len(pairs),'intersecting_triangle_pairs':len(found),'phase_pairs':groups,'examples':[{'rows':[int(row_ids[a]),int(row_ids[b])],'phases':[phases[a],phases[b]],'centers':[rows[row_ids[a],:3].tolist(),rows[row_ids[b],:3].tolist()]} for a,b in list(found)[::max(1,len(found)//20)][:20]]}
report['scope']='Rendered front and back faces in knot region; excludes edge caps and adjacent rows' if thick else 'Mid-surface in knot region; excludes adjacent rows'
Path(sys.argv[1]).with_name('surface-check-thick.json' if thick else 'surface-check.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
sys.exit(1 if len(found) else 0)

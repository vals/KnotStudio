"""Independent finite mid-surface audit. Not a swept collision or thickness certificate."""
import json,sys
from pathlib import Path
import numpy as np
from check_mesh import hits,coplanar,self_test

self_test()
for name in sys.argv[1:]:
    path=Path(name);data=json.loads(path.read_text())
    # Use centimetres to match the existing checker's numerical tolerances.
    p=np.array(data['positions_m'])*100;ids=np.array(data['triangles']);tri=p[ids]
    lo=tri.min(axis=1);hi=tri.max(axis=1);pairs=[]
    for i in range(len(tri)):
        candidates=np.flatnonzero((np.arange(len(tri))>i)&np.all(hi>=lo[i]-1e-9,axis=1)&np.all(hi[i]>=lo-1e-9,axis=1))
        candidates=candidates[~np.any(ids[candidates,:,None]==ids[i,None,:],axis=(1,2))]
        if not len(candidates):continue
        a=np.repeat(tri[i][None],len(candidates),axis=0);b=tri[candidates]
        crossing=hits(a,b)|hits(b,a)
        for j in np.flatnonzero(~crossing):
            if coplanar(a[j],b[j]):crossing[j]=True
        pairs.extend((i,int(j)) for j in candidates[crossing])
    result={'snapshot':path.name,'triangles':len(tri),'intersecting_nonshared_pairs':len(pairs),'examples':pairs[:20],'scope':'Full coarse mid-surface at one instant; excludes shared-vertex pairs. No swept/contact-thickness claim.'}
    path.with_suffix('.audit.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))

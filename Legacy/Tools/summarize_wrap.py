"""Independent saved-mesh deformation and triangle/cylinder interior audit."""
import json,sys
from pathlib import Path
import numpy as np

directory=Path(sys.argv[1] if len(sys.argv)>1 else 'artifacts/cloth-0.7')
history=json.loads((directory/'wrap-history.json').read_text())
assert all(r['triangle_support_gap']>=-1e-10 for r in history)
assert len(history)==331 and all(r['accepted'] for r in history)
assert all(r['state_valid'] and r['collision_safety'] and r['clearance_violations']==0 for r in history[1:])
report={'accepted_frames':330,'duration_s':history[-1]['time'],'max_retries':max(r['retries'] for r in history),'phases':{},'snapshots':[]}
for name,low,high in [('all',0,5.5),('hold',4.25,4.75),('slide',4.75,5.25),('final_hold',5.25,5.5)]:
    rows=[r for r in history if low-1e-7<=r['time']<=high+1e-7]
    report['phases'][name]={'samples_inclusive':len(rows),'rms_min':min(r['rms'] for r in rows),'rms_max':max(r['rms'] for r in rows),'shear_max_degrees':max(r['shear'] for r in rows),'contact_triangles_min':min(r['contact_triangles'] for r in rows),'contact_triangles_max':max(r['contact_triangles'] for r in rows),'triangle_shell_gap_min_m':min(r['triangle_support_gap'] for r in rows),'contact_vertices_min':min(r['contacts'] for r in rows),'contact_vertices_max':max(r['contacts'] for r in rows),'vertex_support_gap_min_m':min(r['support_gap'] for r in rows),'mean_free_x_change_m':rows[-1]['mean_free_x']-rows[0]['mean_free_x']}
for frame in [0,15,75,135,195,255,285,315,330]:
    data=json.loads((directory/f'wrap-{frame}.json').read_text())
    p=np.array(data['positions_m']);ids=np.array(data['triangles']);rest=np.array(data['rest_m']);tri=p[ids]
    # Every triangle stays inside the finite cylinder's axial interval, making
    # the 2D origin-to-projected-triangle distance exact for its capsule gap.
    assert np.all(np.abs(tri[:,:,0])<=.1)
    yz=tri[:,:,[1,2]]-np.array([.16,0]);dist=np.linalg.norm(yz,axis=2).min(axis=1)
    signs=[]
    for i in range(3):
        a=yz[:,i];b=yz[:,(i+1)%3];edge=b-a
        t=np.clip(-np.sum(a*edge,axis=1)/np.maximum(np.sum(edge*edge,axis=1),1e-30),0,1)
        dist=np.minimum(dist,np.linalg.norm(a+t[:,None]*edge,axis=1))
        signs.append(edge[:,0]*(-a[:,1])-edge[:,1]*(-a[:,0]))
    signs=np.stack(signs,axis=1)
    area=(yz[:,1,0]-yz[:,0,0])*(yz[:,2,1]-yz[:,0,1])-(yz[:,1,1]-yz[:,0,1])*(yz[:,2,0]-yz[:,0,0])
    inside=((signs>=0).all(axis=1)|(signs<=0).all(axis=1))&(np.abs(area)>1e-20)
    dist[inside]=0
    dr=np.stack([rest[ids[:,1]]-rest[ids[:,0]],rest[ids[:,2]]-rest[ids[:,0]]],axis=2)
    dx=np.stack([tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]],axis=2)
    stretches=np.linalg.svd(dx@np.linalg.inv(dr),compute_uv=False)
    report['snapshots'].append({'frame':frame,'triangle_midsurface_support_gap_min_m':float(dist.min()-.035),'triangle_shell_support_gap_min_m':float(dist.min()-.035-.00025),'triangles_with_shell_inside_support':int(np.sum(dist<.03525-1e-10)),'principal_stretch_min':float(stretches.min()),'principal_stretch_max':float(stretches.max())})
(directory/'wrap-summary.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))

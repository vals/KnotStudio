"""Audit the exported rendering mesh, not a reconstructed ribbon.

Finite triangle checks exclude triangles sharing a vertex, but include nonshared
triangles in adjacent rows, both faces, long edges and tips. Coplanar overlap is
checked. This is not a continuous-surface or cloth-contact proof.
"""
import argparse,json,itertools
from pathlib import Path
import numpy as np

def hits(a,b):
    e1=b[:,1]-b[:,0];e2=b[:,2]-b[:,0]
    result=np.zeros(len(a),bool)
    for k in range(3):
        origin=a[:,k];direction=a[:,(k+1)%3]-origin
        h=np.cross(direction,e2);det=np.einsum('ij,ij->i',e1,h)
        valid=np.abs(det)>1e-11
        inv=np.divide(1,det,out=np.zeros_like(det),where=valid)
        d=origin-b[:,0];u=inv*np.einsum('ij,ij->i',d,h)
        q=np.cross(d,e1);v=inv*np.einsum('ij,ij->i',direction,q)
        t=inv*np.einsum('ij,ij->i',e2,q)
        result|=valid&(u>=-1e-8)&(v>=-1e-8)&(u+v<=1+1e-8)&(t>=-1e-8)&(t<=1+1e-8)
    return result

def coplanar(a,b):
    n=np.cross(a[1]-a[0],a[2]-a[0]);norm=np.linalg.norm(n)
    if norm<1e-12 or np.max(np.abs((b-a[0])@(n/norm)))>1e-8:return False
    axis=np.argmax(abs(n)); a=np.delete(a,axis,axis=1); b=np.delete(b,axis,axis=1)
    def cross(x,y):return x[0]*y[1]-x[1]*y[0]
    def inside(p,t):
        s=[cross(t[(i+1)%3]-t[i],p-t[i]) for i in range(3)]
        return min(s)>1e-10 or max(s)<-1e-10
    if any(inside(p,b) for p in [*a,a.mean(axis=0)]) or any(inside(p,a) for p in [*b,b.mean(axis=0)]):return True
    for i,j in itertools.product(range(3),repeat=2):
        p,q=a[i],a[(i+1)%3];r,s=b[j],b[(j+1)%3]
        if cross(q-p,r-p)*cross(q-p,s-p)<-1e-16 and cross(s-r,p-r)*cross(s-r,q-r)<-1e-16:return True
    return False

def self_test():
    a=np.array([[0,0,0],[1,0,0],[0,1,0.]])
    b=np.array([[.2,.2,-1],[.2,.2,1],[.8,.2,0.]])
    assert (hits(a[None],b[None])|hits(b[None],a[None]))[0]
    assert coplanar(a,a*.5+.1*np.array([1,1,0]))
    assert coplanar(a,a.copy())
    assert not coplanar(a,a+np.array([2,0,0]))
    assert not coplanar(a,a+np.array([0,0,.1]))

def summary(x):
    return {k:float(v) for k,v in zip(['min','p05','median','p95','max'],np.percentile(x,[0,5,50,95,100]))}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('mesh');parser.add_argument('--full',action='store_true');parser.add_argument('--metrics-only',action='store_true');args=parser.parse_args()
    self_test();data=json.loads(Path(args.mesh).read_text());p=np.array(data['positions']);uv=np.array(data['chart']);front=np.array(data['front']).reshape(-1,3)
    a=p[front];q=uv[front];D=np.stack([q[:,1]-q[:,0],q[:,2]-q[:,0]],axis=-1);E=np.stack([a[:,1]-a[:,0],a[:,2]-a[:,0]],axis=-1)
    F=E@np.linalg.inv(D);stretch=np.linalg.svd(F,compute_uv=False)
    u,v=F[:,:,0],F[:,:,1];cos=np.sum(u*v,axis=1)/(np.linalg.norm(u,axis=1)*np.linalg.norm(v,axis=1));shear=np.degrees(np.arcsin(np.clip(abs(cos),0,1)))
    knot=(a[:,:,1].max(axis=1)>-3)&(a[:,:,1].min(axis=1)<3.5)
    report={'mesh':str(Path(args.mesh).name),'checker_self_tests':'pass','material_assumption':'145 cm assumed flat blank; metric measured against full transverse chart, including compressed folds','metric_all':{'width_stretch':summary(np.linalg.norm(u,axis=1)),'length_stretch':summary(np.linalg.norm(v,axis=1)),'shear_degrees':summary(shear),'principal_stretch_min':float(stretch.min()),'principal_stretch_max':float(stretch.max())},'metric_knot':{'shear_degrees':summary(shear[knot]),'width_stretch':summary(np.linalg.norm(u,axis=1)[knot])}}
    if not args.metrics_only:
        ids=np.concatenate([np.array(data[k]).reshape(-1,3) for k in ['front','back','edges']]);tri=p[ids]
        mask=np.ones(len(tri),bool) if args.full else (tri[:,:,1].max(axis=1)>-3)&(tri[:,:,1].min(axis=1)<3.5)
        ids=ids[mask];tri=tri[mask];lo=tri.min(axis=1);hi=tri.max(axis=1);grid={};size=.20
        for i,(a,b) in enumerate(zip(np.floor(lo/size).astype(int),np.floor(hi/size).astype(int))):
            for cell in itertools.product(*(range(a[k],b[k]+1) for k in range(3))):grid.setdefault(cell,[]).append(i)
        pairs=set()
        for group in grid.values():
            if len(group)<2:continue
            x,y=np.triu_indices(len(group),1);g=np.array(group);i,j=g[x],g[y]
            keep=np.all(hi[i]>=lo[j]-1e-9,axis=1)&np.all(hi[j]>=lo[i]-1e-9,axis=1)
            i,j=i[keep],j[keep]
            keep=~np.any(ids[i,:,None]==ids[j,None,:],axis=(1,2))
            pairs.update(zip(i[keep].tolist(),j[keep].tolist()))
        pairs=np.array(sorted(pairs),dtype=int).reshape(-1,2);found=[];cop=0
        for batch in range(0,len(pairs),50000):
            pair=pairs[batch:batch+50000];a,b=tri[pair[:,0]],tri[pair[:,1]]
            hit=hits(a,b)|hits(b,a)
            na=np.cross(a[:,1]-a[:,0],a[:,2]-a[:,0]);nb=np.cross(b[:,1]-b[:,0],b[:,2]-b[:,0])
            parallel=np.linalg.norm(np.cross(na,nb),axis=1)<1e-8*np.linalg.norm(na,axis=1)*np.linalg.norm(nb,axis=1)
            for i in np.where(parallel&~hit)[0]:
                if coplanar(a[i],b[i]):hit[i]=True;cop+=1
            found.extend(pair[hit].tolist())
        w=data['row_width'];count=data['row_count'];phases=data['phases']
        examples=[];groups={}; kinds={}; group_examples={}
        for i,j in found:
            rows=[int((ids[k,0]//w)%count) for k in [i,j]];phase=[phases[r] for r in rows];key=str(sorted(phase));groups[key]=groups.get(key,0)+1
            kind=str([int(ids[k].min()//(w*count)) if (ids[k]//(w*count)==ids[k,0]//(w*count)).all() else 2 for k in [i,j]])
            kinds[kind]=kinds.get(kind,0)+1
            group_examples.setdefault(key,{'rows':rows,'phases':phase,'kinds':kind,'centers':[tri[i].mean(axis=0).tolist(),tri[j].mean(axis=0).tolist()]})
            if len(examples)<5:examples.append({'rows':rows,'phases':phase,'centers':[tri[i].mean(axis=0).tolist(),tri[j].mean(axis=0).tolist()]})
        report['collision']={'triangles':len(tri),'candidate_pairs':len(pairs),'intersecting_pairs':len(found),'coplanar_pairs':cop,'phase_pairs':groups,'face_pairs':kinds,'group_examples':group_examples,'examples':examples,'scope':'full mesh; excludes shared-vertex pairs' if args.full else 'knot y=-3…3.5 cm; includes front/back/edges/tips; excludes shared-vertex pairs'}
    out=Path(args.mesh).with_name('mesh-audit'+('-full' if args.full else '')+'.json');out.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
    return 1 if report.get('collision',{}).get('intersecting_pairs',0) else 0
if __name__=='__main__':raise SystemExit(main())

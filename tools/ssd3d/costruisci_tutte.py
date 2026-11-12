import sys,json,pickle,cv2;sys.path.insert(0,'/tmp/ssdmap')
import auto,export,copy
exec(open('/tmp/ssdmap/over.py').read())
res=pickle.load(open('/tmp/ssdmap/res.pkl','rb'))
ships=json.load(open('/tmp/sfbwork/ships.json'))['ships']
for sid,(r,keys) in res.items():
    r=copy.deepcopy(r); keys=dict(keys)
    ov=[o for o in O.get(sid,[]) if not o[4].startswith('S:')]
    X0,Y0=r['region'][:2]
    for o in O.get(sid,[]):
        if o[4].startswith('S:'):
            si=int(o[4][2:])-1
            extra=[b for gi,g in enumerate(r['G']) if gi not in r['shields'].values() for b in g if o[0]<=b[0]+b[2]/2-X0<=o[2] and o[1]<=b[1]+b[3]/2-Y0<=o[3]]
            gi_s=r['shields'].get(si)
            if gi_s is not None: r['G'][gi_s]=r['G'][gi_s]+[b for b in extra if b not in r['G'][gi_s]]
            for b in extra: keys.pop(tuple(b),None)
            ov.append((o[0],o[1],o[2],o[3],'-'))
    sysc,wc=export.export(sid,r,keys,ships[sid],ov)
    d=ships[sid]
    miss=[k for k in d['sys'] if k not in sysc and k not in ('prb','apr')]
    wt={}
    for a in d['arm']: wt[a[0]]=wt.get(a[0],0)+a[2]
    wmiss=[k for k in wt if k not in wc]
    if miss or wmiss: print(sid,'mancano',miss,wmiss)
print('fatto',len(res))

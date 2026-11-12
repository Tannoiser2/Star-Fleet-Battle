import cv2,numpy as np,json,sys,pickle
sys.path.insert(0,'/tmp/ssdmap')
OUT='/home/claude/star-fleet-battle/assets/ssd3d/'
def export(sid,r,keys,ship,over=(),blank=()):
    """over: [(x0,y0,x1,y1,chiave)] in coordinate del ritaglio; chiave '-' = nessun cubetto"""
    X0,Y0,X1,Y1=r['region']
    keys=dict(keys)
    for (a,b,c,d,k) in over:
        for bx in list(keys):
            cx,cy=bx[0]+bx[2]/2-X0,bx[1]+bx[3]/2-Y0
            if a<=cx<=c and b<=cy<=d: keys[bx]=k
        if k not in ('-',) and k!='?':
            # caselle non assegnate (scartate) dentro il rettangolo: aggiungile
            for g in r['G']:
                for bx in g:
                    t=tuple(bx)
                    cx,cy=bx[0]+bx[2]/2-X0,bx[1]+bx[3]/2-Y0
                    if t not in keys and a<=cx<=c and b<=cy<=d and t not in [tuple(x) for gi in r['shields'].values() for x in r['G'][gi]]:
                        keys[t]=k
    w,h=X1-X0,Y1-Y0
    res={"w":w,"h":h,"sys":{},"weapt":{},"shield":{}}
    syskeys=set(ship['sys'].keys())
    wtypes=set(a[0] for a in ship['arm'])
    for bx,k in sorted(keys.items(),key=lambda kv:(kv[0][1]//10,kv[0][0])):
        b=[bx[0]-X0,bx[1]-Y0,bx[2],bx[3]]
        if k.startswith('W:'):
            t=k[2:]
            if t not in wtypes:
                # tipo non presente nei dati (es. opzioni): assegna al tipo più simile
                if t.startswith('PH'):
                    alt=[x for x in wtypes if x.startswith('PH')]
                elif t.startswith('PL'):
                    alt=[x for x in wtypes if x.startswith('PL')]
                else: alt=[]
                if not alt: continue
                t=sorted(alt)[0]
            res['weapt'].setdefault(t,[]).append(b)
        elif k in syskeys:
            res['sys'].setdefault(k,[]).append(b)
    for k,gi in r['shields'].items():
        res['shield'][str(k)]=[[bx[0]-X0,bx[1]-Y0,bx[2],bx[3]] for bx in sorted(r['G'][gi],key=lambda q:(q[1]//10,q[0]))]
    im=cv2.imread('/tmp/ssdmap/full/%s.png'%sid,0)
    c=im[Y0:Y1,X0:X1].copy()
    for (a,b,cc,dd) in blank: c[b:dd,a:cc]=255
    work=(c>150).astype(np.uint8)*255
    mask=np.zeros((h+2,w+2),np.uint8)
    ff=work.copy()
    for sx in range(0,w,15):
        for sy in (0,h-1):
            if ff[sy,sx]==255: cv2.floodFill(ff,mask,(sx,sy),128)
    for sy in range(0,h,15):
        for sx in (0,w-1):
            if ff[sy,sx]==255: cv2.floodFill(ff,mask,(sx,sy),128)
    alpha=np.where(ff==128,0,255).astype(np.uint8)
    n,lab,st,_=cv2.connectedComponentsWithStats(alpha)
    for i in range(1,n):
        if st[i,cv2.CC_STAT_AREA]<1500: alpha[lab==i]=0
    alpha=cv2.dilate(alpha,np.ones((5,5),np.uint8))
    ink=c.astype(np.float32)/255.0
    out=np.dstack([(210*ink+30*(1-ink)),(228*ink+18*(1-ink)),(235*ink+20*(1-ink)),alpha]).astype(np.uint8)
    cv2.imwrite(OUT+sid+'.png',out)
    json.dump(res,open(OUT+sid+'.json','w'))
    return {k:len(v) for k,v in res['sys'].items()},{k:len(v) for k,v in res['weapt'].items()}

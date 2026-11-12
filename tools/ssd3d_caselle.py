"""Scheda SSD in 3D.
rileva(): trova le caselle di una scheda SSD (ruotata in orizzontale) e le raggruppa, salvando
un'immagine con i numeri dei gruppi; costruisci(): crea assets/ssd3d/<id>.png e .json dai gruppi
assegnati a mano ai sistemi della nave (chiavi di data/navi.json, "weap" = armi in ordine, s0-s5 scudi)."""
import cv2, numpy as np, json, sys


def rileva(src, x0, y0, x1, y1, out):
    im=cv2.imread(src,0); c=im[y0:y1,x0:x1]
    th=cv2.threshold(c,160,255,cv2.THRESH_BINARY)[1]
    cnts,_=cv2.findContours(th,cv2.RETR_CCOMP,cv2.CHAIN_APPROX_SIMPLE)
    B=[]
    for cn in cnts:
        x,y,w,h=cv2.boundingRect(cn)
        if 12<=w<=30 and 12<=h<=30 and abs(w-h)<=6 and cv2.contourArea(cn)>0.65*w*h:
            cx,cy=x+w/2,y+h/2
            if any(abs(cx-(b[0]+b[2]/2))<8 and abs(cy-(b[1]+b[3]/2))<8 for b in B): continue
            B.append([x,y,w,h])
    # gruppi: caselle che si toccano
    n=len(B); par=list(range(n))
    def f(i):
        while par[i]!=i: par[i]=par[par[i]]; i=par[i]
        return i
    for i in range(n):
        for j in range(i+1,n):
            a,b=B[i],B[j]
            if abs((a[0]+a[2]/2)-(b[0]+b[2]/2))<=a[2]+6 and abs((a[1]+a[3]/2)-(b[1]+b[3]/2))<=a[3]+6:
                par[f(i)]=f(j)
    G={}
    for i in range(n): G.setdefault(f(i),[]).append(B[i])
    groups=sorted(G.values(),key=lambda g:(min(b[1] for b in g)//20,min(b[0] for b in g)))
    vis=cv2.cvtColor(c,cv2.COLOR_GRAY2BGR)
    big=cv2.resize(vis,None,fx=1.6,fy=1.6)
    cols=[(0,0,255),(0,160,0),(255,0,0),(0,140,255),(200,0,200),(0,200,200)]
    for gi,g in enumerate(groups):
        col=cols[gi%6]
        for (x,y,w,h) in g: cv2.rectangle(big,(int(x*1.6),int(y*1.6)),(int((x+w)*1.6),int((y+h)*1.6)),col,2)
        gx=min(b[0] for b in g); gy=min(b[1] for b in g)
        cv2.putText(big,str(gi),(int(gx*1.6)-4,int(gy*1.6)+14),cv2.FONT_HERSHEY_SIMPLEX,0.75,(255,255,255),5)
        cv2.putText(big,str(gi),(int(gx*1.6)-4,int(gy*1.6)+14),cv2.FONT_HERSHEY_SIMPLEX,0.75,col,2)
    cv2.imwrite(out+'.png',big)
    json.dump({"x0":x0,"y0":y0,"w":x1-x0,"h":y1-y0,"groups":groups},open(out+'.json','w'))
    print(len(B),'caselle',len(groups),'gruppi',[len(g) for g in groups])
    


def costruisci(sid, full, det, assign, blank=(), outdir='assets/ssd3d/'):
    d=json.load(open(det))
    x0,y0,w,h=d['x0'],d['y0'],d['w'],d['h']
    im=cv2.imread(full,0); c=im[y0:y0+h,x0:x0+w].copy()
    for (a,b,cc,dd) in blank: c[b:dd,a:cc]=255
    G=d['groups']
    res={"w":w,"h":h,"sys":{},"weap":[],"shield":{}}
    for k,gl in assign.items():
        boxes=[]
        for gi in gl: boxes+=sorted(G[gi],key=lambda r:(r[1]//10,r[0]))
        if k=="weap":
            res["weap"]=[]
            for gi in gl: res["weap"]+=sorted(G[gi],key=lambda r:(r[1]//10,r[0]))
        elif k.startswith("s") and k[1:].isdigit():
            res["shield"][k[1:]]=boxes
        else:
            res["sys"][k]=boxes
    # sfondo trasparente fuori dalla sagoma
    work=(c>150).astype(np.uint8)*255
    mask=np.zeros((h+2,w+2),np.uint8)
    ff=work.copy()
    for sx in range(0,w,20):
        for sy in (0,h-1):
            if ff[sy,sx]==255: cv2.floodFill(ff,mask,(sx,sy),128)
    for sy in range(0,h,20):
        for sx in (0,w-1):
            if ff[sy,sx]==255: cv2.floodFill(ff,mask,(sx,sy),128)
    alpha=np.where(ff==128,0,255).astype(np.uint8)
    # via i frammenti isolati piccoli (scritte fuori dalla sagoma)
    n,lab,st,_=cv2.connectedComponentsWithStats(alpha)
    for i in range(1,n):
        if st[i,cv2.CC_STAT_AREA]<1500: alpha[lab==i]=0
    alpha=cv2.dilate(alpha,np.ones((5,5),np.uint8))
    ink=c.astype(np.float32)/255.0
    out=np.dstack([(210*ink+30*(1-ink)),(228*ink+18*(1-ink)),(235*ink+20*(1-ink)),alpha]).astype(np.uint8)
    cv2.imwrite(outdir+sid+'.png',out)
    json.dump(res,open(outdir+sid+'.json','w'))
    print(sid,w,h,{k:len(v) for k,v in res['sys'].items()},'armi',[len(x) for x in res['weap']],{k:len(v) for k,v in res['shield'].items()})


# Assegnazioni usate (numeri dei gruppi di rileva())
B10 = {"s0": [0], "s1": [3], "s2": [24], "s3": [53], "s4": [23], "s5": [2],
	"br": [7, 14, 32], "em": [11], "bt": [12, 28], "tr": [15, 30], "sh": [16, 47], "lab": [17], "cw": [20, 21], "fh": [22],
	"imp": [25, 43, 45], "ah": [26], "aux": [29], "trac": [35, 50, 52], "apr": [36], "prb": [37], "lw": [42], "rw": [46],
	"weap": [38, 39, 18, 19, 51, 1, 6, 8, 27, 31, 33, 34, 40, 41, 13, 44]}
# kli_b10: rileva(scheda, 1140, 280, 2000, 1365, ...); costruisci(..., blank=[(755, 0, 860, 90), (0, 0, 70, 40)])
# fed_ca: rileva(scheda, 1440, 380, 2200, 1500, ...)

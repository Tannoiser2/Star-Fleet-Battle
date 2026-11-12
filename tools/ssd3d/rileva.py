import cv2,numpy as np,json,re,sys,os
from rapidocr_onnxruntime import RapidOCR
OCR=None
def ocr_labels(path,cache):
    global OCR
    if os.path.exists(cache): return json.load(open(cache))
    if OCR is None: OCR=RapidOCR()
    im=cv2.imread(path)
    big=cv2.resize(im,None,fx=1.5,fy=1.5,interpolation=cv2.INTER_CUBIC)
    res,_=OCR(big)
    out=[]
    for box,txt,conf in (res or []):
        xs=[p[0]/1.5 for p in box]; ys=[p[1]/1.5 for p in box]
        out.append([min(xs),min(ys),max(xs),max(ys),txt])
    json.dump(out,open(cache,'w')); return out

def ocr_region(path,reg,cache):
    global OCR
    if os.path.exists(cache): return json.load(open(cache))
    if OCR is None: OCR=RapidOCR()
    im=cv2.imread(path)
    X0,Y0,X1,Y1=reg
    out=[]
    T=360
    for ty in range(Y0,Y1,T-60):
        for tx in range(X0,X1,T-60):
            c=im[ty:min(ty+T,Y1),tx:min(tx+T,X1)]
            if c.size==0: continue
            big=cv2.resize(c,None,fx=2.0,fy=2.0,interpolation=cv2.INTER_CUBIC)
            res,_=OCR(big)
            for box,txt,conf in (res or []):
                xs=[p[0]/2+tx for p in box]; ys=[p[1]/2+ty for p in box]
                r=[min(xs),min(ys),max(xs),max(ys),txt]
                # scarta i doppioni delle sovrapposizioni
                if any(abs(r[0]-o[0])<8 and abs(r[1]-o[1])<8 and o[4]==txt for o in out): continue
                out.append(r)
    json.dump(out,open(cache,'w')); return out

def boxes_groups(gray):
    th=cv2.threshold(gray,160,255,cv2.THRESH_BINARY)[1]
    cnts,_=cv2.findContours(th,cv2.RETR_CCOMP,cv2.CHAIN_APPROX_SIMPLE)
    B=[]
    for cn in cnts:
        x,y,w,h=cv2.boundingRect(cn)
        if 12<=w<=30 and 12<=h<=30 and abs(w-h)<=6 and cv2.contourArea(cn)>0.65*w*h:
            cx,cy=x+w/2,y+h/2
            if any(abs(cx-(b[0]+b[2]/2))<8 and abs(cy-(b[1]+b[3]/2))<8 for b in B): continue
            B.append([x,y,w,h])
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
    return [sorted(g,key=lambda r:(r[1]//10,r[0])) for g in G.values()]

def gbox(g):
    return [min(b[0] for b in g),min(b[1] for b in g),max(b[0]+b[2] for b in g),max(b[1]+b[3] for b in g)]

def rdist(a,b):
    dx=max(a[0]-b[2],b[0]-a[2],0); dy=max(a[1]-b[3],b[1]-a[3],0)
    return (dx*dx+dy*dy)**0.5

KEYS=[('FORWARDHULL','fh'),('FWDHULL','fh'),('FHULL','fh'),('REARHULL','ah'),('AFTHULL','ah'),('AHULL','ah'),('RHULL','ah'),('CENTERHULL','ch'),('CHULL','ch'),('HULL','HULL'),
 ('LWARP','lw'),('RWARP','rw'),('CWARP','cw'),('CENTERWARP','cw'),('WARP','cw'),('IMPULSE','imp'),('IMP','imp'),('BRIDGE','br'),('FLAG','fl'),('EMER','em'),('AUX','aux'),
 ('BATTERY','bt'),('BTTY','bt'),('BATT','bt'),('LAB','lab'),('TRAC','trac'),('TRAN','tr'),('SHUTTLE','sh'),('SHTL','sh'),('SHUT','sh'),('PROBE','prb'),('PRB','prb'),
 ('APR','apr'),('AWR','apr'),('CARGO','cargo'),('ARMOR','armor'),('ARMOUR','armor'),
 ('PHOT','W:PHOT'),('PH-1','W:PH1'),('PH1','W:PH1'),('PH-2','W:PH2'),('PH2','W:PH2'),('PH-3','W:PH3'),('PH3','W:PH3'),('PH-G','W:PH1'),
 ('DISR','W:DISR'),('DRONE','W:DRN'),('DRN','W:DRN'),('PL-R','W:PLR'),('PLR','W:PLR'),('PL-S','W:PLS'),('PLS','W:PLS'),('PL-G','W:PLG'),('PLG','W:PLG'),('PL-F','W:PLF'),('PLF','W:PLF'),
 ('OPT','W:OPT'),('SENSOR','X'),('SCANNER','X'),('DAMCON','X'),('DAM','X'),('EXDAM','X'),('EXCESS','X'),('SECURITY','X'),('ADD','X'),('SFG','X'),('WEB','X'),('CLOAK','X'),('CNTR','X'),('MECH','X')]

def classify(tok):
    t=tok.upper().replace(' ','').replace('_','-')
    t=re.sub(r'PH-?(\d)',r'PH-\1',t)
    for k,v in KEYS:
        if k in t: return v
    return None

def labels_from(ocr):
    out=[]
    for x0,y0,x1,y1,txt in ocr:
        t=re.sub(r'(PH|PL|DISR)-\s+',r'\1-',txt.upper())
        toks=t.split()
        # spezza in parole con rettangolo proporzionale
        tot=sum(len(k) for k in toks)+len(toks)-1 or 1
        pos=0
        for tk in toks:
            a=x0+(x1-x0)*pos/tot; b=x0+(x1-x0)*(pos+len(tk))/tot
            pos+=len(tk)+1
            # parole incollate (es. "PH-1-RHTRAN"): spezza ai nomi noti
            cuts=sorted(set([0]+[m.start() for k,_ in KEYS for m in re.finditer(re.escape(k),tk) if m.start()>0 and not any(k2!=k and k in k2 and tk.find(k2)>=0 and tk.find(k2)<=m.start()<tk.find(k2)+len(k2) for k2,_ in KEYS)]))
            cuts=[c for i,c in enumerate(cuts) if i==0 or c-cuts[i-1]>=2]
            cuts.append(len(tk))
            for ci in range(len(cuts)-1):
                p0,p1=cuts[ci],cuts[ci+1]
                out.append([a+(b-a)*p0/len(tk),y0,a+(b-a)*p1/len(tk),y1,tk[p0:p1]])
    # unisci lettere singole con la parola seguente
    res=[]
    i=0
    while i<len(out):
        a=out[i]
        if a[4] in ('L','R','C','F','A') and i+1<len(out) and out[i+1][1]==a[1]:
            b=out[i+1]; res.append([a[0],a[1],b[2],b[3],a[4]+b[4]]); i+=2; continue
        res.append(a); i+=1
    return [[*r,classify(r[4])] for r in res]

def shield_labels(ocr):
    s={}
    for x0,y0,x1,y1,txt in ocr:
        t=txt.upper().replace(' ','')
        m=re.search(r'SHIELD[#*]?(\d)',t)
        if m: s[int(m.group(1))-1]=[x0,y0,x1,y1]
    return s

def run(sid,full,ship,cache):
    gray=cv2.imread(full,0)
    ocr=ocr_labels(full,cache)
    G=boxes_groups(gray)
    sl=shield_labels(ocr)
    shields={}
    used=set()
    for k in sorted(sl):
        best=None;bd=1e9
        for gi,g in enumerate(G):
            if gi in used or len(g)<6: continue
            d=rdist(sl[k],gbox(g))
            if d<bd: bd=d;best=gi
        if best is not None and bd<120:
            shields[k]=best; used.add(best)
    # regione: unione degli scudi
    if len(shields)<4: return None,'scudi trovati %d'%len(shields)
    bb=[gbox(G[g]) for g in shields.values()]
    X0=int(min(b[0] for b in bb))-12; Y0=int(min(b[1] for b in bb))-12; X1=int(max(b[2] for b in bb))+12; Y1=int(max(b[3] for b in bb))+12
    labs=[l for l in labels_from(ocr) if l[5] and X0-20<=l[0] and l[2]<=X1+20 and Y0-20<=l[1] and l[3]<=Y1+20]
    syskeys=set(ship['sys'].keys())
    assign={}
    for gi,g in enumerate(G):
        if gi in used: continue
        gb=gbox(g)
        if not (gb[0]>=X0 and gb[2]<=X1 and gb[1]>=Y0 and gb[3]<=Y1): continue
        best=None;bd=1e9
        for l in labs:
            d=rdist(l[:4],gb)
            # preferisci le scritte sopra il gruppo
            if l[3]<=gb[1]+4 and l[2]>gb[0]-10 and l[0]<gb[2]+10: d*=0.6
            if d<bd: bd=d;best=l
        key=best[5] if best and bd<70 else '?'
        if key=='HULL':
            key='ch' if 'ch' in syskeys else ('fh' if 'fh' in syskeys else 'ah')
        if key=='cw' and 'cw' not in syskeys and len(g)>=4:
            cx=(gb[0]+gb[2])/2; key='lw' if cx<(X0+X1)/2 else 'rw'
        if key=='W:OPT': key='W:DISR'
        assign[gi]=key
    return dict(G=G,shields=shields,region=[X0,Y0,X1,Y1],assign=assign),None

COL={}
def color(k):
    import hashlib
    if k not in COL:
        h=int(hashlib.md5(k.encode()).hexdigest()[:6],16)
        COL[k]=((h&255)//2+100,((h>>8)&255)//2+60,((h>>16)&255)//2+60)
    return COL[k]

def white_regions(gray):
    wm=(gray>160).astype(np.uint8)
    n,lab=cv2.connectedComponents(wm,connectivity=4)
    return lab

def region_at(lab,pts):
    h,w=lab.shape
    c={}
    for x,y in pts:
        x=int(min(max(x,0),w-1)); y=int(min(max(y,0),h-1))
        v=lab[y,x]
        if v: c[v]=c.get(v,0)+1
    return max(c,key=c.get) if c else 0

def per_box(r,ocr,ship,gray):
    """assegna ogni casella all'etichetta più vicina (preferendo quelle sopra), poi a maggioranza nel gruppo
    connesso fra caselle con la stessa etichetta"""
    X0,Y0,X1,Y1=r['region']
    labs=[l for l in labels_from(ocr) if l[5] and X0-20<=l[0] and l[2]<=X1+20 and Y0-20<=l[1] and l[3]<=Y1+20]
    syskeys=set(ship['sys'].keys())
    lab=white_regions(gray)
    for l in labs:
        x0,y0,x1,y1=l[:4]
        l.append(region_at(lab,[(x0-3,y0-3),(x1+3,y0-3),(x0-3,y1+3),(x1+3,y1+3),((x0+x1)/2,y0-4),((x0+x1)/2,y1+4)]))
    texts=[t[:4] for t in ocr]
    allb=[b for g in r['G'] for b in g]
    med=float(np.median([b[2] for b in allb]))
    out={}
    for gi,g in enumerate(r['G']):
        if gi in r['shields'].values(): continue
        gb=gbox(g)
        if not (gb[0]>=X0 and gb[2]<=X1 and gb[1]>=Y0 and gb[3]<=Y1): continue
        gbx=gbox(g)
        for b in g:
            cx,cy=b[0]+b[2]/2,b[1]+b[3]/2
            if b[2]<0.72*med: continue
            bb=[b[0],b[1],b[0]+b[2],b[1]+b[3]]
            reg=region_at(lab,[(gbx[0]-3,cy),(gbx[2]+3,cy),(cx,gbx[1]-3),(cx,gbx[3]+3)])
            cand=[l for l in labs if l[6]==reg] or labs
            best=None;bd=1e9
            for l in cand:
                d=rdist(l[:4],bb)
                if l[3]<=bb[1]+4 and l[2]>bb[0]-6 and l[0]<bb[2]+6: d*=0.3
                elif l[1]>=bb[3]-4: d*=1.6
                if d<bd: bd=d;best=l
            key=best[5] if best and bd<120 else '?'
            if key=='HULL':
                if 'ch' in syskeys: key='ch'
                elif 'fh' in syskeys and 'ah' in syskeys: key='fh' if best[1]<(Y0+Y1)/2-60 else 'ah'
                else: key='fh' if 'fh' in syskeys else 'ah'
            if key in ('cw',) and 'cw' not in syskeys: key='lw' if cx<(X0+X1)/2 else 'rw'
            if key=='W:OPT': key='W:DISR'
            out[tuple(b)]=key
    return out

def draw(sid,full,r,keys,outp):
    im=cv2.imread(full)
    X0,Y0,X1,Y1=r['region']
    c=im[Y0:Y1,X0:X1].copy()
    for b,k in keys.items():
        x,y,w,h=b[0]-X0,b[1]-Y0,b[2],b[3]
        cv2.rectangle(c,(x,y),(x+w,y+h),color(k),-1)
        cv2.putText(c,k.replace('W:','')[:4],(x+1,y+h-6),cv2.FONT_HERSHEY_PLAIN,0.62,(255,255,255),1)
    for gi,g in enumerate(r['G']):
        if gi in r['shields'].values(): continue
        gb=gbox(g)
        if not (gb[0]>=X0 and gb[2]<=X1 and gb[1]>=Y0 and gb[3]<=Y1): continue
        p=(int(gb[0]-X0)-2,int(gb[1]-Y0)+11)
        cv2.putText(c,str(gi),p,cv2.FONT_HERSHEY_SIMPLEX,0.5,(255,255,255),4)
        cv2.putText(c,str(gi),p,cv2.FONT_HERSHEY_SIMPLEX,0.5,(0,0,200),1)
    for k,gi in r['shields'].items():
        for b in r['G'][gi]:
            x,y=b[0]-X0,b[1]-Y0
            cv2.rectangle(c,(x,y),(x+b[2],y+b[3]),(255,200,120),2)
        b=r['G'][gi][0]
        cv2.putText(c,'S%d'%(k+1),(b[0]-X0,b[1]-Y0-2),cv2.FONT_HERSHEY_SIMPLEX,0.7,(255,120,0),2)
    cv2.imwrite(outp,c)

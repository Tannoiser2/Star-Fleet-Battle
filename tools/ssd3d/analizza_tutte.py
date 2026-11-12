import sys,json,cv2;sys.path.insert(0,'/tmp/ssdmap')
import auto,pickle
from collections import Counter
ships=json.load(open('/tmp/sfbwork/ships.json'))['ships']
ids=json.load(open('ids.json'))
res={}
for sid in ids:
    r,err=auto.run(sid,'full/%s.png'%sid,ships[sid],'ocr/%s.json'%sid)
    if err:
        print(sid,'ERRORE',err,flush=True); continue
    o2=auto.ocr_region('full/%s.png'%sid,r['region'],'ocr/%s_r.json'%sid)
    keys=auto.per_box(r,o2,ships[sid],cv2.imread('full/%s.png'%sid,0))
    auto.draw(sid,'full/%s.png'%sid,r,keys,'/tmp/ssdmap/rev_%s.png'%sid)
    res[sid]=(r,keys)
    print(sid,r['region'],len(r['shields']),dict(Counter(keys.values())),flush=True)
pickle.dump(res,open('res.pkl','wb'))

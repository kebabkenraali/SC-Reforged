import struct, collections, os
F=open(os.path.join(os.environ.get('SC_GAME_DIR', r'C:\Gog games\Strike Commander'), 'SC.dat'),'rb')
def sec(n,c=1):
    out=b''
    for i in range(c):
        F.seek((n+i)*2352+16); out+=F.read(2048)
    return out
pvd=sec(16); root=pvd[156:156+34]
def walk(lba,size,path):
    d=sec(lba,(size+2047)//2048); i=0; res=[]
    while i<len(d):
        l=d[i]
        if l==0: i=(i//2048+1)*2048; continue
        r=d[i:i+l]; elba,esz=struct.unpack_from('<I',r,2)[0],struct.unpack_from('<I',r,10)[0]
        fl=r[25]; nl=r[32]; name=r[33:33+nl]
        if name not in (b'\0',b'\1'):
            nm=name.decode().split(';')[0]
            if fl&2: res+=walk(elba,esz,path+nm+'/')
            else: res.append((path+nm,elba,esz))
        i+=l
    return res
files={f[0]:f for f in walk(struct.unpack_from('<I',root,2)[0],struct.unpack_from('<I',root,10)[0],'/')}
def isofile(p):
    _,l,s=files[p]; return sec(l,(s+2047)//2048)[:s]
def tre(d):
    n,_=struct.unpack_from('<II',d,0); out={}
    for i in range(n):
        e=d[8+i*74:8+(i+1)*74]; name=e[1:66].split(b'\0')[0].decode('latin1')
        o,s=struct.unpack_from('<II',e,66); out[name]=d[o:o+s]
    return out
B=tre(isofile('/BIGTRE.TRE'))
def get(n): return B['..\\..\\DATA\\'+n.replace('/','\\')]
def chunks(d):
    i=0; out=[]
    while i+8<=len(d):
        tag=d[i:i+4].decode('latin1'); sz=struct.unpack_from('>I',d,i+4)[0]
        if tag in ('FORM','CAT ','LIST'): out.append((tag+':'+d[i+8:i+12].decode('latin1'),d[i+12:i+8+sz]))
        else: out.append((tag,d[i+8:i+8+sz]))
        i+=8+sz+(sz&1)
    return out
def dump(d,ind=0,maxd=60):
    for tag,body in chunks(d):
        if ':' in tag:
            print(' '*ind+tag,len(body)); dump(body,ind+2,maxd)
        else: print(' '*ind+tag,len(body),body[:maxd].hex())
def pak(d):
    first=struct.unpack_from('<I',d,4)[0]&0xffffff
    offs=[]; i=4
    while i<first:
        v=struct.unpack_from('<I',d,i)[0]; offs.append((v&0xffffff,v>>24)); i+=4
    offs.append((len(d),0))
    return [(d[offs[k][0]:offs[k+1][0]],offs[k][1]) for k in range(len(offs)-1)]
def lzw(data):
    pos=0; nbits=9; total=len(data)*8
    dic=[bytes([i]) for i in range(256)]+[b'',b'']
    prev=None; out=bytearray()
    while pos+nbits<=total:
        v=(int.from_bytes(data[pos>>3:(pos>>3)+3],'little')>>(pos&7))&((1<<nbits)-1); pos+=nbits
        if v==256: dic=dic[:258]; nbits=9; prev=None; continue
        if v==257: break
        if prev is None: out+=dic[v]; prev=dic[v]; continue
        e=dic[v] if v<len(dic) else prev+prev[:1]
        out+=e
        if len(dic)<4096: dic.append(prev+e[:1])
        prev=e
        if len(dic)>=(1<<nbits) and nbits<12: nbits+=1
    return bytes(out)

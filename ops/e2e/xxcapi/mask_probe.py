"""Measure whether a masked edit was honored: red-fill fraction inside vs outside the mask hole.
usage: python3 mask_probe.py <result image> <mask png> [original]"""
import sys
from PIL import Image
import numpy as np
res=Image.open(sys.argv[1]).convert('RGB'); mask=Image.open(sys.argv[2]).convert('RGBA')
mask=mask.resize(res.size, Image.NEAREST); hole=np.array(mask)[:,:,3]==0
a=np.array(res).astype(int); red=(a[:,:,0]>170)&(a[:,:,1]<90)&(a[:,:,2]<90)
print(f'{sys.argv[1]}: size={res.size} red inside hole={red[hole].mean()*100:.1f}%  red outside hole={red[~hole].mean()*100:.2f}%')
if len(sys.argv)>3:
    o=Image.open(sys.argv[3]).convert('RGB').resize(res.size, Image.LANCZOS)
    d=np.abs(np.array(o).astype(int)-a).mean(axis=2)
    print(f'   mean abs change inside hole={d[hole].mean():.1f}  outside={d[~hole].mean():.1f}  outside pixels changed>40: {(d[~hole]>40).mean()*100:.1f}%')

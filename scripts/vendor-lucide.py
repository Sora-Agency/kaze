#!/usr/bin/env python3
import concurrent.futures
import math
import pathlib
import re
import urllib.request
import xml.etree.ElementTree as ET

COMMIT = "70562c1ee1c4fdcf736fe97bc893fb8511927934"
ICONS = "activity arrow-down-to-line arrow-up arrow-up-right box calendar-clock calendar-plus check chevron-down chevron-left chevron-right circle-alert circle-question-mark download file file-text folder folder-minus folder-plus hard-drive hammer house info layout-grid link monitor moon pencil play plus refresh-cw search shield-check shield-alert smartphone sparkles sun trash x".split()
ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "src/Icons/Lucide"

def fetch(name):
    cached = ASSETS / f"{name}.svg"
    if cached.exists(): return name, cached.read_bytes()
    url = f"https://raw.githubusercontent.com/lucide-icons/lucide/{COMMIT}/icons/{name}.svg"
    try:
        data = urllib.request.urlopen(url, timeout=30).read()
    except Exception as error:
        raise RuntimeError(f"Could not vendor {name}: {error}") from error
    ET.fromstring(data)
    (ASSETS / f"{name}.svg").write_bytes(data)
    return name, data

def point(x, y):
    return f"CGPoint(x: {x:.8g}, y: {y:.8g})"

def arc(x, y, rx, ry, rotation, large, sweep, ex, ey):
    if (x, y) == (ex, ey): return []
    if rx == 0 or ry == 0: return [f"p.addLine(to: {point(ex, ey)})"]
    rx, ry = abs(rx), abs(ry)
    phi = math.radians(rotation); c, s = math.cos(phi), math.sin(phi)
    dx, dy = (x-ex)/2, (y-ey)/2
    xp, yp = c*dx+s*dy, -s*dx+c*dy
    scale = xp*xp/(rx*rx)+yp*yp/(ry*ry)
    if scale > 1: rx *= math.sqrt(scale); ry *= math.sqrt(scale)
    coefficient = math.sqrt(max(0, (rx*rx*ry*ry-rx*rx*yp*yp-ry*ry*xp*xp)/(rx*rx*yp*yp+ry*ry*xp*xp)))
    if bool(large) == bool(sweep): coefficient *= -1
    cxp, cyp = coefficient*rx*yp/ry, -coefficient*ry*xp/rx
    cx, cy = c*cxp-s*cyp+(x+ex)/2, s*cxp+c*cyp+(y+ey)/2
    start = math.atan2((yp-cyp)/ry, (xp-cxp)/rx)
    end = math.atan2((-yp-cyp)/ry, (-xp-cxp)/rx)
    delta = (end-start) % (2*math.pi)
    if not sweep and delta > 0: delta -= 2*math.pi
    count = max(1, math.ceil(abs(delta)/(math.pi/2)))
    def position(t): return (cx+rx*c*math.cos(t)-ry*s*math.sin(t), cy+rx*s*math.cos(t)+ry*c*math.sin(t))
    def derivative(t): return (-rx*c*math.sin(t)-ry*s*math.cos(t), -rx*s*math.sin(t)+ry*c*math.cos(t))
    result = []
    for i in range(count):
        a, b = start+delta*i/count, start+delta*(i+1)/count
        k = 4/3*math.tan((b-a)/4)
        pa, pb = position(a), position(b); da, db = derivative(a), derivative(b)
        cp1, cp2 = (pa[0]+k*da[0], pa[1]+k*da[1]), (pb[0]-k*db[0], pb[1]-k*db[1])
        result.append(f"p.addCurve(to: {point(*pb)}, control1: {point(*cp1)}, control2: {point(*cp2)})")
    return result

def path_commands(data):
    tokens = re.findall(r"[A-Za-z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?", data)
    i = 0; command = ""; x = y = sx = sy = 0; control = None; last = ""
    lines = []
    while i < len(tokens):
        if tokens[i].isalpha(): command = tokens[i]; i += 1
        upper, relative = command.upper(), command.islower()
        if upper == "Z":
            lines.append("p.closeSubpath()"); x, y = sx, sy; control = None; last = upper; command = ""; continue
        sizes = {"M":2,"L":2,"H":1,"V":1,"C":6,"S":4,"Q":4,"T":2,"A":7}
        if upper not in sizes: raise ValueError(f"Unsupported SVG command: {command}")
        n = sizes[upper]
        if upper == "A":
            values = [float(t) for t in tokens[i:i+3]]; i += 3
            for _ in range(2):
                token = tokens[i]
                if token[0] not in "01": raise ValueError("Invalid arc flag")
                values.append(float(token[0]))
                if len(token) > 1: tokens[i] = token[1:]
                else: i += 1
            values.extend(float(t) for t in tokens[i:i+2]); i += 2
        else:
            values = [float(t) for t in tokens[i:i+n]]; i += n
        def xy(a,b): return (a+x,b+y) if relative else (a,b)
        if upper in ["M","L","T"]:
            ex,ey=xy(*values)
            if upper == "M": lines.append(f"p.move(to: {point(ex,ey)})"); sx,sy=ex,ey; command="l" if relative else "L"
            elif upper == "L": lines.append(f"p.addLine(to: {point(ex,ey)})")
            else:
                cp=(2*x-control[0],2*y-control[1]) if last in ["Q","T"] else (x,y)
                lines.append(f"p.addQuadCurve(to: {point(ex,ey)}, control: {point(*cp)})"); control=cp
        elif upper in ["H","V"]:
            ex,ey=(values[0]+(x if relative else 0),y) if upper=="H" else (x,values[0]+(y if relative else 0))
            lines.append(f"p.addLine(to: {point(ex,ey)})")
        elif upper in ["C","S","Q"]:
            pts=[xy(*values[j:j+2]) for j in range(0,n,2)]; ex,ey=pts[-1]
            if upper=="S":pts.insert(0,(2*x-control[0],2*y-control[1]) if last in ["C","S"] else (x,y))
            if upper=="Q":lines.append(f"p.addQuadCurve(to: {point(ex,ey)}, control: {point(*pts[0])})")
            else:lines.append(f"p.addCurve(to: {point(ex,ey)}, control1: {point(*pts[0])}, control2: {point(*pts[1])})")
            control=pts[-2]
        else:
            rx,ry,rotation,large,sweep,ex,ey=values;ex,ey=xy(ex,ey)
            lines.extend(arc(x,y,rx,ry,rotation,large,sweep,ex,ey))
        x,y=ex,ey;last=upper
        if upper not in ["C","S","Q","T"]:control=None
    return lines

def geometry(svg):
    lines=[]
    for element in ET.fromstring(svg):
        kind=element.tag.split("}")[-1];a=element.attrib
        if kind=="path":lines.extend(path_commands(a["d"]))
        elif kind in ["polyline","polygon"]:
            nums=[float(t) for t in re.findall(r"[-+]?\d*\.?\d+",a['points'])]
            lines.extend([f"p.{'move' if i==0 else 'addLine'}(to: {point(*nums[i:i+2])})" for i in range(0,len(nums),2)])
            if kind=="polygon":lines.append("p.closeSubpath()")
        elif kind=="line":lines.extend([f"p.move(to: {point(float(a['x1']),float(a['y1']))})",f"p.addLine(to: {point(float(a['x2']),float(a['y2']))})"])
        elif kind in ["circle","ellipse"]:
            cx,cy=float(a['cx']),float(a['cy']);rx=float(a.get('r',a.get('rx')));ry=float(a.get('r',a.get('ry')))
            lines.append(f"p.addEllipse(in: CGRect(x: {cx-rx:.8g}, y: {cy-ry:.8g}, width: {2*rx:.8g}, height: {2*ry:.8g}))")
        elif kind=="rect":
            x,y,w,h=[float(a.get(k,0)) for k in ['x','y','width','height']];rx=float(a.get('rx',0));ry=float(a.get('ry',rx))
            lines.append(f"p.addRoundedRect(in: CGRect(x: {x}, y: {y}, width: {w}, height: {h}), cornerSize: CGSize(width: {rx}, height: {ry}))")
        else:raise ValueError(f"Unsupported SVG element {kind}")
    return lines

def main():
    ASSETS.mkdir(parents=True,exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:data=dict(pool.map(fetch,ICONS))
    license_path = ASSETS / "LICENSE"
    if not license_path.exists():
        license_data = urllib.request.urlopen(f"https://raw.githubusercontent.com/lucide-icons/lucide/{COMMIT}/LICENSE", timeout=30).read()
        license_path.write_bytes(license_data)
    output=[f"import SwiftUI\n\nenum LucidePaths {{\n    static func path(_ name: String) -> Path {{\n        var p = Path()\n        switch name {{"]
    for name in sorted(data):
        output.append(f'        case "{name}":')
        output.extend('            '+line for line in geometry(data[name]))
    output.append('        default: assertionFailure("Unknown Lucide icon: \\(name)")\n        }\n        return p\n    }\n}\n')
    (ROOT/'src/DesignSystem/LucidePaths.generated.swift').write_text('\n'.join(output))
    print(f"Vendored {len(data)} Lucide icons at {COMMIT}")

if __name__=="__main__":main()

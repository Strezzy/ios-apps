#!/usr/bin/env python3
"""Final color and legibility corrections from the actual WebKit captures."""
from pathlib import Path
R=Path(__file__).resolve().parents[1]/'EnterTheThirdDimension/Resources/Game'
p=R/'visuals.js';s=p.read_text()
s=s.replace('color*1.20','color*1.03').replace('),upward)*.70','),upward)*.57').replace('(wrap*.84)','(wrap*.80)')
s=s.replace('glow*(.19+uPulse*.22)','glow*(.08+uPulse*.22)')
s=s.replace('vec3 albedo=pow(max(base,vec3(.001)),vec3(2.2));','''if((material>.5&&material<1.5)||ground){
        float broadLuma=dot(base,vec3(.299,.587,.114));base=mix(vec3(broadLuma),base,.87);
      }
      vec3 albedo=pow(max(base,vec3(.001)),vec3(2.2));''') if 'broadLuma' not in s else s
p.write_text(s)
p=R/'cozy.css';s=p.read_text()
if 'Final capture review' not in s:
 s+='''
/* Final capture review: explicit dimension states keep text readable. */
#objectiveText{color:#425c43}
#hud{color:#355340;text-shadow:0 1px 0 #fff8e560}
.chapter-mark small{color:#426849}.chapter-mark strong{color:#35553f}
.mini-prism{color:#c59451;text-shadow:0 1px 0 #fff6d8}
#dimensionBadge,.in3d #dimensionBadge{color:#46694e;text-shadow:0 1px 0 #fff6d9}
#dimensionBadge i{color:#557454}
.title-content .primary,.modal-card .primary{background:#426d57;color:#fff3d9;border:1px solid #517d63;border-radius:20px;box-shadow:0 4px 0 #2d5444,0 10px 24px #243c2820}
.title-content .primary:active,.modal-card .primary:active{background:#345946;transform:translateY(3px);box-shadow:0 1px 0 #2d5444}
.title-content>p{color:#597155}
.in3d #movePad{background:radial-gradient(circle,#fff5dfeb,#e4e6cde8);border-color:#fff9e4d9;box-shadow:0 4px 0 #55714b66,inset 0 2px 0 #fffdf1}
.in3d #power{background:linear-gradient(145deg,#d1e4c5f2,#abc9a9ee);border-color:#f0f5dce8;box-shadow:0 4px 0 #668b6b66}
.in3d #power svg{stroke:#496e55}
.in3d #jump{background:linear-gradient(145deg,#ffdfa2,#ecc085);border-color:#fff3c9;box-shadow:0 5px 0 #c5986477}
#jump.pressed,.in3d #jump.pressed{background:#efc287;transform:translateY(3px) scale(.97);box-shadow:0 2px 0 #c5986477}
.control-label{color:#38563e;text-shadow:0 1px 0 #fff6db80}
#results{color:#8d642f}.modal-card>p,.modal-card p.key-help{color:#63765d}
'''
p.write_text(s)
print('Applied reviewed color, bloom and touch-control contrast refinements')

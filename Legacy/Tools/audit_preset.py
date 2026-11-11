"""Read the emitted mesh, independently measure its visible material metric.

No solver input or photo assets are involved. Report stretch, not physical proof.
"""
import json
import sys
import numpy as np

path = sys.argv[1] if len(sys.argv) > 1 else 'artifacts/premade-0.8/final/surface.json'
data = json.load(open(path))
p = np.asarray(data['positions'])
uv = np.asarray(data['chart'])
part = next(p for p in data['parts'] if p['name'] == 'front wrap')
first, rows, columns = part['first'], part['rows'], part['columns']
# Front-facing meridians; omit only the explicitly rolled top/bottom edges.
values = []
for row in range(rows//4, rows*3//4):
    for col in range(int(columns*.10), int(columns*.82)):
        a = first + row*columns + col
        for ids in [[a,a+1,a+columns],[a+1,a+columns+1,a+columns]]:
            pos = p[ids]
            tex = uv[ids]
            world = (pos[1:]-pos[0]).T
            material = (tex[1:]-tex[0]).T
            values.append(np.linalg.svd(world @ np.linalg.inv(material), compute_uv=False))
values = np.asarray(values)
print('Visible front-wrap principal surface/material ratios:')
print('  minimum %.4f; median %.4f; 95th percentile %.4f; maximum %.4f' % (
    values.min(),np.median(values),np.percentile(values,95),values.max()))
# Broad bounds detect the former shrinking-full-texture chart defect. The
# report retains the actual measurements instead of calling the surface isometric.
assert values.min() > .88 and values.max() < 1.15
print('PASS: visible wrap retains motif scale within the stated authored approximation.')

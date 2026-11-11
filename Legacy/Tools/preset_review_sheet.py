"""Compose unretouched offscreen evidence; never includes reference photographs."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
root=Path('artifacts/premade-0.8/final')
out=Path('deliverables/premade-0.8');out.mkdir(parents=True,exist_ok=True)
font_path='/System/Library/Fonts/Helvetica.ttc'
font=ImageFont.truetype(font_path,25)
small=ImageFont.truetype(font_path,18)
def sheet(name,title,columns,rows,entries,footer):
    tile=580;top=86;label=42;bottom=56
    canvas=Image.new('RGB',(columns*tile,top+rows*(tile+label)+bottom),'#edf0f4')
    draw=ImageDraw.Draw(canvas);draw.text((24,24),title,font=font,fill='#1b2938')
    for i,(image_path,text) in enumerate(entries):
        x=(i%columns)*tile;y=top+(i//columns)*(tile+label)
        image=Image.open(image_path).convert('RGB').resize((tile,tile),Image.Resampling.LANCZOS)
        canvas.paste(image,(x,y));draw.text((x+18,y+tile+10),text,font=small,fill='#1b2938')
    draw.text((22,canvas.height-37),footer,font=small,fill='#415164')
    canvas.save(out/name)
p=lambda mode:root/f'four-in-hand-{mode}.png'
sheet('four-in-hand-material-review-0.8.png','KnotStudio 0.8 | Authored four-in-hand',3,2,[
(p('gray'),'Plain gray | front'),(p('dots'),'Pin dots | front'),(p('fabric'),'Regimental | front'),
(p('gray-side'),'Plain gray | oblique'),(p('dots-side'),'Pin dots | oblique'),(p('side'),'Regimental | oblique')],
'Actual SceneKit snapshots. Authored approximation; reference photographs are not included.')
before=Path('artifacts/premade-0.8/focused-before')
sheet('four-in-hand-before-after-0.8.png','Four-in-hand | Legacy route, first preset, focused correction',3,2,[
(p('legacy-gray'),'Legacy 0.7 | front'),(before/'four-in-hand-gray.png','Initial 0.8 | front'),(p('gray'),'Revised 0.8 | front'),
(p('legacy-gray-side'),'Legacy 0.7 | oblique'),(before/'four-in-hand-gray-side.png','Initial 0.8 | oblique'),(p('gray-side'),'Revised 0.8 | oblique')],
'Matched cameras (scale 4.7), gray, lights and AO 0.85 in every column. No retouching.')

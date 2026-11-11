from PIL import Image,ImageDraw,ImageFont
from pathlib import Path
out=Path('Tests/Fixtures');out.mkdir(parents=True,exist_ok=True)
im=Image.new('RGB',(512,256));d=ImageDraw.Draw(im)
for box,color in [((0,0,255,127),(220,35,45)),((256,0,511,127),(25,190,75)),((0,128,255,255),(35,80,220)),((256,128,511,255),(240,190,25))]:d.rectangle(box,fill=color)
f=ImageFont.load_default(size=26)
for xy,label in [((25,20),'TL'),((420,20),'TR'),((25,210),'BL'),((420,210),'BR')]:d.text(xy,label,font=f,fill='white')
d.rectangle((155,84,345,170),fill='white');d.text((178,88),'UP',font=f,fill='black');d.line([(255,126),(255,94)],fill='black',width=4);d.polygon([(255,87),(248,101),(262,101)],fill='black');d.text((166,137),'RIGHT ->',font=f,fill='black')
im.save(out/'orientation.png',dpi=(72,72));im.save(out/'orientation-dpi.png',dpi=(72,288))
ex=Image.Exif();ex[274]=6
im.save(out/'orientation-exif6.jpg',exif=ex,quality=98,subsampling=0,dpi=(72,288))
for orientation in range(1,9):
 ex=Image.Exif();ex[274]=orientation
 im.save(out/f'orientation-exif{orientation}.jpg',exif=ex,quality=98,subsampling=0,dpi=(72,288))
print('Created asymmetric 512 × 256 PNG, unequal-DPI PNG, EXIF-6 JPEG')

"""Regenerate logo-derived SVG compositions. Optional PNGs use CairoSVG (development only)."""
from pathlib import Path
import math

ASSETS = Path('site/assets')
PALM = '''<g stroke="#221211" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round">
<path fill="url(#flesh)" d="M90 237C92 207 76 188 65 165L31 111Q25 99 32 95Q39 92 45 101L67 126Q71 128 69 119L47 53Q44 43 51 41Q59 38 62 50L86 105Q89 109 89 101L82 25Q81 14 89 14Q97 14 98 26L109 98Q110 106 113 99L123 23Q125 12 133 14Q141 16 137 29L131 105Q130 111 134 106L163 44Q168 34 175 38Q181 41 176 53L150 123Q145 138 153 132L183 111Q192 105 197 111Q202 118 191 127L167 150C156 162 155 177 150 194L137 239Z"/>
<path fill="#a23c36" d="M98 232Q111 197 98 157Q95 141 78 124Q107 137 117 161Q116 124 127 105Q118 145 127 175Q147 147 167 140Q142 164 139 199L132 234Z"/>
<path fill="none" stroke="#e7c3b8" stroke-width="3" d="M97 225Q108 191 97 161M115 224Q125 190 115 156M131 225Q128 189 145 165M82 146Q102 163 104 184M109 126Q110 143 116 155"/>
<path fill="none" stroke-width="1.3" d="M98 233Q110 199 100 172M110 234Q128 192 117 168M130 235Q135 207 136 186M81 153Q94 169 95 185M68 127L85 143M58 69L72 66M63 81L77 76M67 94L82 89M85 41L99 41M87 54L102 53M89 70L104 66M92 86L106 80M121 46L136 48M119 62L134 64M116 80L133 82M153 65L166 72M148 80L161 87M143 96L155 102M179 115L184 123M165 127L172 134"/>
<path fill="#e7e1df" d="M83 233L144 231L149 251L81 256Z"/>
<path fill="none" d="M87 241L139 238M87 247L140 244"/>
</g>'''
THUMB = '''<g stroke="#221211" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"><path fill="url(#flesh)" d="M75 235L68 169Q65 149 78 127L96 96L101 42Q102 25 114 24Q130 25 127 45L125 108L170 111Q194 107 198 122Q199 130 192 135Q208 147 197 159Q209 176 194 184Q201 200 184 207L139 218L139 239Z"/><path fill="#a23c36" d="M90 230Q77 177 112 138Q94 176 113 198L130 233ZM118 109Q109 140 129 160L179 173Q147 175 128 166Q104 147 108 124Z"/><path fill="none" d="M127 136L185 139M127 158L190 162M128 181L187 186M125 201L177 205M103 60L125 63M101 76L124 79M99 93L123 96M79 173Q86 201 93 214"/><path fill="none" stroke="#e7c3b8" stroke-width="3" d="M97 225Q81 189 103 159M111 48L111 105Q92 135 89 154"/><path fill="#e7e1df" d="M69 231L145 230L146 251L71 255Z"/><path fill="none" d="M77 240L139 237M77 248L137 244"/></g>'''
DEFS = '''<defs><linearGradient id="flesh" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#f2dbd0"/><stop offset=".52" stop-color="#c97e70"/><stop offset="1" stop-color="#a23c36"/></linearGradient><g id="palm">'''+PALM+'''</g><g id="thumb">'''+THUMB+'''<use href="#palm" transform="translate(74 -6) rotate(-24) scale(.16)"/><use href="#palm" transform="translate(108 -19) rotate(10) scale(.15)"/><use href="#palm" transform="translate(131 19) rotate(35) scale(.15)"/><use href="#palm" transform="translate(131 62) rotate(50) scale(.14)"/></g><g id="hand"><use href="#palm"/>
<use href="#palm" transform="translate(24 21) rotate(-31) scale(.23)"/>
<use href="#palm" transform="translate(68 -24) rotate(-13) scale(.22)"/>
<use href="#palm" transform="translate(121 -34) rotate(13) scale(.22)"/>
<use href="#palm" transform="translate(166 -1) rotate(31) scale(.22)"/>
<use href="#palm" transform="translate(201 69) rotate(44) scale(.2)"/>
</g></defs>'''
def svg(content, width=800, height=600):
 return f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{width}" height="{height}" viewBox="0 0 {width} {height}">{DEFS}{content}</svg>'
def hand(x,y,s=1,r=0):
 return f'<use href="#hand" transform="translate({x} {y}) rotate({r}) scale({s})"/>'
def thumb(x,y,s=1,r=0):
 return f'<use href="#thumb" transform="translate({x} {y}) rotate({r}) scale({s})"/>'
ASSETS.mkdir(exist_ok=True)
(ASSETS/'hand.svg').write_text(svg('<symbol id="swarm-hand" viewBox="0 -50 250 310"><use href="#hand"/></symbol><symbol id="thumb-hand" viewBox="0 -50 250 310"><use href="#thumb"/></symbol><use href="#hand" transform="translate(0 50)"/>',250,310))
scenes = [
 hand(350,340,1.25,180) + ''.join(hand(x,y,.18,r) for x,y,r in [(210,60,-35),(350,95,30),(70,130,-22),(390,215,60)]),
 ''.join(hand(250+math.cos(i*1.2)*105,190+math.sin(i*1.2)*70,.58,i*50-90) for i in range(9)),
 hand(105,86,1.1,-14) + '<g transform="translate(325 115) rotate(180)"><path fill="#e7e1df" stroke="#0c0c0c" stroke-width="3" d="M0 -75L48 0L0 30L-48 0Z M-48 10L0 82L48 10L0 42Z"/></g>' + thumb(348,180,.28,18)
]
for i,scene in enumerate(scenes):
 (ASSETS/f'beat-{i+1}.svg').write_text(svg(scene,480,380))

compositions = [
 ''.join(hand(50+i*128,150+(i%2)*35,.85,i*8-16)+f'<circle cx="{160+i*128}" cy="415" r="35" fill="#e7e1df" stroke="#a23c36" stroke-width="6"/><text x="{160+i*128}" y="422" text-anchor="middle" fill="#0c0c0c" font-family="monospace" font-size="21">$EHS</text>' for i in range(5)),
 ''.join(f'<path d="M{x} {y}l8 12m-8 0l8 -12" stroke="#a23c36" stroke-width="3"/>' for x,y in [(70,65),(185,90),(640,85),(700,330),(90,420),(570,400),(390,45)]) + thumb(200,90,1.5,0) + '<text x="630" y="350" fill="#e7e1df" font-family="monospace" font-size="62">0%</text>',
 hand(180,130,1.2,-30) + '<path d="M440 90l110 60v140l-110 60-110-60V150Z M440 90v140m-110-80l110 80 110-80m-110 80v120" fill="#a23c36" stroke="#e7e1df" stroke-width="3"/>' + ''.join(hand(350+(i%3)*48,150+(i//3)*60,.24,i*12) for i in range(6)),
 '<rect x="270" y="350" width="270" height="75" rx="38" fill="#a23c36" stroke="#e7e1df" stroke-width="3"/><text x="405" y="397" text-anchor="middle" fill="white" font-family="monospace" font-size="26">Buy $EHS</text>' + hand(450,80,1,90)+''.join(hand(190+i*70,150,.3,40) for i in range(4)),
 '<ellipse cx="420" cy="360" rx="290" ry="90" fill="#a23c36" stroke="#e7e1df" stroke-width="3"/>' + hand(180,90,1.1,-15)+f'<g opacity=".5">{hand(370,505,.7,180)}</g><text x="600" y="150" fill="#e7e1df" font-family="monospace" font-size="80">?</text>',
 '<path d="M80 370L190 310 270 330 350 240 470 275 590 180 700 230" fill="none" stroke="#e7e1df" stroke-width="8"/>' + ''.join(hand(100+i*92,60+(i%3)*30,.65,i*9-22) for i in range(6))
]
captions = ['When you try to HODL but your hands multiply.', 'POV: The dev says 0% tax and actually means it.', 'Everyone else: diamond hands. Us: fractal meat-hand.', 'When you finally find the buy button.', 'Liquidity so deep, you don’t know whose hand it is anymore.', 'Buy pressure? Sorry, we call it swarm density.']
for i,(scene,caption) in enumerate(zip(compositions,captions)):
 import textwrap,html
 lines=textwrap.wrap(caption,48)
 captionSvg=''.join(f'<text x="400" y="{525+j*27}" text-anchor="middle" fill="#e7e1df" font-family="monospace" font-size="22">{html.escape(line)}</text>' for j,line in enumerate(lines))
 if i==1: captionSvg+='<text x="400" y="596" text-anchor="middle" fill="#e7e1df" font-family="monospace" font-size="14">Token transfers only. Swaps: 2% hook + 1.25% pool fee.</text>'
 art=svg('<rect width="800" height="620" fill="#0c0c0c"/><path d="M20 20H780V600H20Z" fill="none" stroke="#a23c36" stroke-width="2"/>'+scene+captionSvg,800,620)
 (ASSETS/f'meme-{i+1}.svg').write_text(svg('<rect width="800" height="500" fill="#0c0c0c"/>'+scene,800,500))
 render=Path('test/scratch/meme-render');render.mkdir(parents=True,exist_ok=True)
 (render/f'meme-{i+1}.svg').write_text(art)
 try:
  import cairosvg
  # CairoSVG uses xlink:href for SVG 1.1 use instances.
  cairosvg.svg2png(bytestring=art.replace('href=', 'xlink:href=').encode(),write_to=str(ASSETS/f'meme-{i+1}.png'))
 except ImportError: pass
print('Generated logo-derived hand illustrations and six unique memes.')

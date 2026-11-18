// Development-time converter. Node.js built-ins only; the plugin never runs it.
// Code: GPL-3.0-only. Generated data: CC-BY-SA-3.0 (see Data/StrokeReference/NOTICE.md).
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const root = path.resolve(import.meta.dirname, '..');
const upstream = process.argv[2];
if (!upstream) throw Error('Usage: node Tools/build_stroke_reference.mjs <pinned fude-kana-data directory>');
const hash = b => crypto.createHash('sha256').update(b).digest('hex');
const out = path.join(root, 'Data/StrokeReference');
fs.mkdirSync(out, {recursive:true});
// Representative manuscript forms, independently authored; no font outlines.
// Multiple M commands delimit pen lifts. a/g are single-storey handwriting forms.
const latin = {
 A:'M50 5 L15 95 M50 5 L85 95 M28 62 L72 62', B:'M20 5 L20 95 M20 5 C95 0 95 49 20 49 C100 45 100 100 20 95',
 C:'M85 20 C10 -30 -5 125 85 80', D:'M20 5 L20 95 M20 5 C110 0 110 100 20 95',
 E:'M20 5 L20 95 M20 5 L80 5 M20 48 L70 48 M20 95 L80 95', F:'M20 5 L20 95 M20 5 L80 5 M20 48 L70 48',
 G:'M85 20 C10 -30 -5 125 85 80 L85 55 L55 55', H:'M20 5 L20 95 M80 5 L80 95 M20 50 L80 50',
 I:'M20 5 L80 5 M50 5 L50 95 M20 95 L80 95', J:'M20 5 L80 5 M65 5 L65 75 C65 110 15 100 15 75',
 K:'M20 5 L20 95 M80 5 L20 55 M42 37 L85 95', L:'M20 5 L20 95 L80 95',
 M:'M15 5 L15 95 M15 5 L50 60 L85 5 L85 95', N:'M20 5 L20 95 M20 5 L80 95 M80 5 L80 95',
 O:'M50 5 C-5 5 -5 95 50 95 C105 95 105 5 50 5', P:'M20 5 L20 95 M20 5 C100 -5 100 60 20 50',
 Q:'M50 5 C-5 5 -5 95 50 95 C105 95 105 5 50 5 M60 70 L95 105',
 R:'M20 5 L20 95 M20 5 C100 -5 100 60 20 50 M50 50 L85 95',
 S:'M85 15 C0 -25 0 50 50 50 C110 50 100 120 15 85', T:'M10 5 L90 5 M50 5 L50 95',
 U:'M20 5 L20 65 C20 110 80 110 80 65 L80 5', V:'M15 5 L50 95 L85 5',
 W:'M5 5 L25 95 L50 35 L75 95 L95 5', X:'M15 5 L85 95 M85 5 L15 95',
 Y:'M15 5 L50 50 M85 5 L50 50 M50 50 L50 95', Z:'M15 5 L85 5 L15 95 L85 95',
 a:'M75 40 C15 10 5 100 55 90 C80 85 75 50 75 40 M75 35 L75 95',
 b:'M20 5 L20 95 M20 55 C80 -5 110 105 20 90', c:'M80 45 C10 5 0 120 80 85',
 d:'M75 40 C15 10 5 100 55 90 C80 85 75 50 75 40 M75 5 L75 95',
 e:'M20 60 L80 60 C90 10 0 20 20 75 C30 100 60 100 85 85',
 f:'M80 10 C40 -5 35 15 35 35 L35 95 M15 40 L75 40',
 g:'M75 40 C15 10 5 100 55 90 C80 85 75 50 75 40 M75 35 L75 105 C75 135 30 140 15 120',
 h:'M20 5 L20 95 M20 60 C20 25 80 20 80 60 L80 95',
 i:'M50 40 L50 95 M50 10 L50 12', j:'M60 40 L60 110 C60 135 30 140 15 120 M60 10 L60 12',
 k:'M20 5 L20 95 M80 35 L20 70 M45 55 L85 95', l:'M50 5 L50 95',
 m:'M15 35 L15 95 M15 55 C15 20 50 20 50 55 L50 95 M50 55 C50 20 85 20 85 55 L85 95',
 n:'M20 35 L20 95 M20 60 C20 20 80 20 80 60 L80 95',
 o:'M50 35 C5 35 5 95 50 95 C95 95 95 35 50 35',
 p:'M20 35 L20 135 M20 55 C80 -5 110 105 20 90',
 q:'M75 40 C15 10 5 100 55 90 C80 85 75 50 75 40 M75 35 L75 135',
 r:'M25 35 L25 95 M25 60 C25 25 60 25 75 40',
 s:'M80 40 C10 10 5 65 50 65 C100 65 90 115 15 90',
 t:'M45 10 L45 75 C45 100 65 100 80 85 M15 40 L80 40',
 u:'M20 35 L20 75 C20 110 75 100 75 65 M75 35 L75 95',
 v:'M15 35 L50 95 L85 35', w:'M5 35 L25 95 L50 50 L75 95 L95 35',
 x:'M15 35 L85 95 M85 35 L15 95', y:'M15 35 L50 95 M85 35 L35 135',
 z:'M15 35 L85 35 L15 95 L85 95',
 0:'M50 5 C-5 5 -5 95 50 95 C105 95 105 5 50 5',
 1:'M25 30 L50 5 L50 95 M25 95 L80 95', 2:'M15 25 C25 -15 95 0 80 35 L15 95 L85 95',
 3:'M15 10 C100 -20 100 50 45 48 C105 40 105 125 15 90',
 4:'M65 5 L15 65 L90 65 M65 5 L65 95', 5:'M80 5 L20 5 L20 45 C110 20 110 125 15 85',
 6:'M80 10 C25 -10 0 95 50 95 C110 95 85 20 25 55', 7:'M15 5 L85 5 L35 95',
 8:'M50 45 C-20 10 65 -20 85 15 C110 55 -10 55 20 85 C50 125 130 80 50 45',
 9:'M75 45 C15 80 -5 0 50 5 C110 5 85 100 25 95'
};
function parse(s) {
 const t=s.match(/[MLC]|-?\d+(?:\.\d+)?/g); let i=0, p=[0,0], strokes=[], points;
 const xy=()=>[+t[i++]/150,+t[i++]/150];
 while(i<t.length) { const op=t[i++]; if(op==='M'){p=xy();points=[p];strokes.push({points});}
 else if(op==='L'){p=xy();points.push(p);} else if(op==='C'){const a=p,b=xy(),c=xy(),d=xy();
 for(let k=1;k<=24;k++){const u=k/24,v=1-u;points.push([v*v*v*a[0]+3*v*v*u*b[0]+3*v*u*u*c[0]+u*u*u*d[0],v*v*v*a[1]+3*v*v*u*b[1]+3*v*u*u*c[1]+u*u*u*d[1]]);} p=d;
 } else throw Error(op); }
 const all=strokes.flatMap(s=>s.points),lo=[0,1].map(k=>Math.min(...all.map(p=>p[k]))),hi=[0,1].map(k=>Math.max(...all.map(p=>p[k])));
 for(const s of strokes)s.points=s.points.map(p=>p.map((v,k)=>0.05+0.9*(v-lo[k])/Math.max(hi[k]-lo[k],0.01)));
 return strokes;
}
function resample(points) {
 const d=[0]; for(let i=1;i<points.length;i++) d.push(d.at(-1)+Math.hypot(points[i][0]-points[i-1][0],points[i][1]-points[i-1][1]));
 if(d.at(-1)<=0) throw Error('Empty stroke');
 const n=Math.min(96,Math.max(16,Math.ceil(d.at(-1)*80))), result=[];let j=1;
 for(let i=0;i<n;i++){const v=d.at(-1)*i/(n-1);while(j<d.length-1&&d[j]<v)j++;const f=(v-d[j-1])/(d[j]-d[j-1]||1);
 result.push([points[j-1][0]+(points[j][0]-points[j-1][0])*f,points[j-1][1]+(points[j][1]-points[j-1][1])*f]);}return result;
}
const index=JSON.parse(fs.readFileSync(path.join(upstream,'kana-data/index.json'),'utf8'));
if(index.count!==176||index.kana.length!==176)throw Error('Unexpected upstream index');
const inputs=[], entries=index.kana.map(k=>{const p=path.join(upstream,'kana-data',k.file), b=fs.readFileSync(p), g=JSON.parse(b);
 inputs.push({file:k.file,sha256:hash(b)});
 if(g.character!==k.character||g.strokes.length!==g.strokeCount||g.strokeCount!==k.strokeCount)throw Error(k.file);
 return {code:g.character.codePointAt(0),source:1,strokes:g.strokes};});
for(const [c,s] of Object.entries(latin))entries.push({code:c.codePointAt(0),source:2,strokes:parse(s)});
entries.sort((a,b)=>a.code-b.code);
if(hash(JSON.stringify(inputs))!=='01a63c4a0da45507a9580e111bd54954ff848801f838fe33e4d198c97b37afcc')throw Error('Input JSON differs from the pinned upstream commit');
if(entries.length!==238||new Set(entries.map(e=>e.code)).size!==238)throw Error('Coverage');
const bodies=entries.map(e=>{const a=[e.strokes.length,0]; for(const s of e.strokes){const pts=resample(s.points);a.push(s.isCurl?1:0,0,pts.length,0);
 for(const p of pts)for(const v of p){if(!Number.isFinite(v)||v<0||v>1)throw Error('Coordinate '+e.code+' '+v);const n=Math.round(v*65535);a.push(n&255,n>>8);}}return Buffer.from(a);});
const total=16+entries.length*16+bodies.reduce((n,b)=>n+b.length,0), data=Buffer.alloc(total);
data.write('AWSTREF1');data.writeUInt32LE(entries.length,8);data.writeUInt32LE(total,12);let offset=16+entries.length*16;
entries.forEach((e,i)=>{const k=16+i*16;data.writeUInt32LE(e.code,k);data.writeUInt32LE(offset,k+4);data.writeUInt32LE(bodies[i].length,k+8);data.writeUInt32LE(e.source,k+12);bodies[i].copy(data,offset);offset+=bodies[i].length;});
fs.writeFileSync(path.join(out,'StrokeReference.bin'),data);
const lines=[];for(let i=0;i<data.length;i+=24)lines.push('  '+Array.from(data.subarray(i,i+24),v=>'$'+v.toString(16).padStart(2,'0').toUpperCase()).join(',')+(i+24<data.length?',':''));
fs.writeFileSync(path.join(out,'StrokeReference.inc'),'// CC-BY-SA-3.0; generated by Tools/build_stroke_reference.mjs; see NOTICE.md\r\n'+lines.join('\r\n')+'\r\n');
fs.writeFileSync(path.join(out,'StrokeReferenceSize.inc'),String(data.length-1)+'\r\n');
fs.writeFileSync(path.join(out,'Manifest.json'),JSON.stringify({format:'AWSTREF1',license:'CC-BY-SA-3.0',kana:176,latin:62,bytes:total,sha256:hash(data),upstream:{repository:'https://github.com/karimghezali/fude-kana-data',commit:'ab69a27e2f5a5125ac89b5f13a1b0f0e318d5319',archiveSHA256:'c2aa4c0165bd76933c0468073755e252e279d1aa93fe0b32e2a3471e33fb823e'},inputs},null,2)+'\n');
console.log(JSON.stringify({characters:entries.length,bytes:total,sha256:hash(data)}));

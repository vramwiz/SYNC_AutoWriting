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
// Alternate guides for printed forms, keeping the canonical pen lifts.
const kanaVariants = {
  き: ['M6 23 C30 23 60 20 90 17 M3 46 C28 46 72 42 98 40 M43 0 C45 25 54 52 70 66 M70 66 C54 64 22 62 11 76 C-3 95 28 103 83 98'],
  さ: ['M4 28 C28 28 65 23 95 16 M39 0 C46 23 60 49 74 65 M74 65 C51 53 25 57 12 71 C-2 91 27 103 85 98'],
  な: ['M3 23 C13 32 37 26 57 19 M33 0 C49 6 35 47 8 81 M60 38 C69 34 76 35 83 39 C91 41 98 44 100 49 M83 39 C65 42 66 57 69 75 C75 97 51 110 37 97 C28 87 40 79 54 80 C73 82 88 89 100 98'],
  ふ: [
    'M39 0 C39 11 55 17 57 23 M57 23 C30 34 37 48 51 60 C70 77 73 101 42 95 L24 86 M3 84 C4 104 15 92 24 86 L56 67 M56 67 C71 56 90 66 99 77 C101 83 93 84 85 86',
    'M27 3 C35 11 55 0 72 8 M46 22 C40 37 62 48 63 68 C68 90 52 101 33 86 M22 46 C21 69 12 77 4 88 M77 39 C87 48 94 65 97 86',
  ],
  ほ: [
    'M12 3 C5 22 3 66 8 96 M35 11 L91 9 M34 39 L98 37 M69 10 C71 32 71 59 72 75 C75 96 63 103 48 99 C29 96 34 74 49 72 C68 68 83 78 97 90',
    'M6 2 C20 15 0 34 2 66 C1 80 3 88 9 96 C6 84 12 68 19 51 M37 17 C49 9 67 6 80 9 M42 30 C34 46 45 50 85 37 M60 24 C74 24 65 46 68 65 C72 87 62 101 50 95 C36 95 33 82 46 77 C58 69 78 78 92 89',
  ],
  む: [
    'M3 24 C10 38 37 25 55 16 M24 0 C39 6 29 34 29 54 C28 82 4 73 9 55 C12 43 27 41 30 52 C37 61 16 77 18 87 C17 100 38 103 66 98 C87 95 83 85 80 72 C76 56 66 32 77 28 M77 28 C86 24 96 35 98 44 C100 52 89 50 85 53',
  ],
  も: [
    'M25 0 C41 5 29 18 24 45 C14 68 13 97 36 100 C71 107 81 72 49 48 M1 21 C6 34 21 32 28 31 M16 33 C1 38 -2 54 4 60 C11 67 26 70 34 68',
  ],
  ゆ: [
    'M5 16 C15 21 1 49 7 70 L7 72 C9 55 31 30 49 23 C70 11 90 13 96 39 C102 61 84 77 58 74 C37 73 28 51 32 24 C33 6 48 -6 56 3 M56 3 C71 17 66 51 60 74 C52 90 45 98 37 99',
  ],
  ゑ: [
    'M29 9 C43 8 62 3 70 6 L59 8 L19 49 C33 38 46 29 66 30 C94 28 97 53 79 62 C66 71 52 72 40 69 C29 64 39 47 51 50 C72 54 49 69 42 74 L8 104 C23 92 30 85 40 90 C49 96 52 108 64 95 C76 82 89 79 99 87 C105 94 108 104 97 104 L88 105',
    'M27 3 C45 5 65 1 78 3 L74 7 C58 23 43 31 21 39 C30 32 47 25 60 24 C86 20 104 30 104 47 C98 67 70 69 47 62 C38 56 43 43 55 44 C73 48 58 66 35 77 L15 87 C32 76 38 81 46 91 C58 109 67 97 76 85 C87 75 101 76 111 91',
  ],
  り: [
    'M4 0 C15 7 6 23 4 38 C3 47 5 59 7 64 M6 57 C15 40 17 19 31 11 C50 9 53 56 43 77 C35 89 24 98 8 101',
  ],
  れ: [
    'M22 0 C36 7 28 29 28 53 L28 99 M4 34 C8 43 22 39 31 34 C34 35 31 43 28 52 L8 81 C10 76 23 61 35 49 C52 34 72 10 77 23 C85 33 73 65 76 79 C82 105 104 84 110 69',
  ],
  わ: [
    'M32 0 L32 101 M8 21 L31 21 C32 31 32 49 28 58 L5 86 C17 73 28 56 42 43 C60 25 86 23 101 35 C127 57 113 91 64 101',
  ],
  ん: [
    'M47 4 C48 14 32 40 20 66 L4 98 C13 78 23 55 34 50 C45 44 56 48 60 63 C64 85 65 99 81 99 C98 100 109 83 111 61',
  ],
};
const katakanaVariants = {
  ア: [
    'M3 5 C10 15 15 11 23 10 C44 7 64 4 81 4 C88 5 83 11 75 18 C67 25 58 31 49 35 M40 21 C51 19 53 27 49 35 C46 56 37 76 17 91',
  ],
  ゥ: [
    'M39 4 L39 21 M5 21 L5 46 M6 21 L73 21 C84 49 54 82 25 85',
    'M37 4 L37 25 M6 25 L6 47 M6 25 L68 25 C79 25 70 50 65 60 C58 72 46 83 34 85',
  ],
  タ: [
    'M36 1 C48 6 47 16 36 27 C27 40 19 48 9 54 M41 19 C51 23 67 16 75 20 C76 31 64 45 58 50 C48 66 35 81 2 97 M35 43 C49 46 59 54 69 66',
    'M45 4 C37 10 37 24 27 35 L7 56 M36 22 L84 22 C87 37 73 61 67 72 C57 86 37 98 15 103 M34 48 C45 48 65 61 79 72',
  ],
  ネ: [
    'M42 1 C49 4 55 9 58 14 M14 31 C20 45 41 33 58 30 C84 24 66 39 55 51 C40 71 22 82 3 89 M54 53 L54 102 M70 55 C78 59 87 64 90 73',
    'M55 5 L55 24 M14 24 L82 24 C84 33 67 45 58 52 C43 61 24 70 4 75 M55 56 L55 103 M76 60 L106 77',
  ],
  ム: [
    'M38 1 C52 7 43 23 32 43 C25 55 21 68 16 73 C10 76 5 74 2 69 C5 75 11 76 24 73 L80 64 M64 45 C75 49 83 64 88 77',
    'M52 5 C48 25 34 56 24 83 C23 89 12 84 5 94 C12 87 23 89 39 88 L103 84 M80 52 C95 72 104 86 111 97',
  ],
};
const doubleStorey = {
  a: 'M12 23 C19 5 46 0 67 9 C84 14 82 35 82 53 L82 100 M82 48 C60 45 15 51 9 73 C1 103 43 113 82 87',
  g: 'M48 4 C18 4 10 15 10 26 C10 56 82 58 83 26 C83 13 69 4 48 4 M29 47 C13 53 13 64 35 66 C63 68 90 63 90 82 C90 109 8 110 8 83 C8 76 15 69 25 65 M75 12 L99 6',
};
const latinPrint = {
  M: [
    'M15 5 L15 90 M15 5 L53 85 L92 5 L92 90',
    'M16 7 L15 87 L5 90 M4 2 C12 2 18 5 24 13 L54 85 L90 8 C93 10 95 14 95 24 L95 84 L111 89',
  ],
  N: [
    'M8 5 L8 91 M8 5 L46 91 M46 5 L46 91',
    'M6 4 C16 4 18 9 17 20 L17 84 C17 88 15 89 10 90 M18 8 L77 85 M88 3 C79 3 77 7 77 15 L77 89',
  ],
  T: ['M3 17 C4 10 4 2 13 2 L72 2 C79 2 81 7 82 17 M41 3 L41 86'],
  W: [
    'M15 0 L36 90 L59 2 L82 90 L105 0',
    'M16 2 L39 82 L58 22 L78 82 L106 2',
  ],
  b: ['M18 4 L18 90 M18 50 C31 33 56 40 57 63 C60 88 38 101 18 85'],
  d: ['M48 45 C31 27 7 38 7 62 C6 88 31 96 48 83 M48 4 L48 91'],
  g: [
    'M27 4 C-1 4 0 42 27 42 C54 42 54 4 27 4 M18 40 C8 49 12 57 28 57 C54 55 59 70 43 79 C18 93 -5 72 14 56',
    'M53 12 C36 -6 8 0 7 28 C5 53 29 69 53 53 M53 6 L53 77 C52 100 25 105 10 91',
  ],
  h: ['M16 5 L16 92 M16 53 C31 36 51 36 52 58 L52 92'],
  k: ['M15 5 L15 92 M49 41 L15 67 M30 55 L47 84 L58 94'],
  m: ['M14 5 L14 54 M14 16 C24 -2 49 -1 49 18 L49 54 M49 17 C62 -3 85 -1 85 18 L85 54'],
  n: ['M14 5 L14 54 M14 15 C24 -2 52 -2 52 18 L52 54'],
  p: ['M16 5 L16 85 M16 13 C32 -7 57 3 58 26 C60 48 36 65 16 50'],
  q: ['M49 14 C31 -6 7 3 6 27 C6 51 29 66 49 50 M49 5 L49 85'],
  r: ['M14 5 L14 54 M14 19 C19 6 29 -2 39 6'],
  u: ['M15 5 L15 38 C15 61 36 62 51 48 M51 5 L51 54'],
  v: ['M12 2 L32 54 L51 2'],
  w: ['M13 2 L28 54 L46 11 L64 54 L81 2'],
  x: ['M12 2 L45 52 M45 2 L12 52'],
};

function fitToBounds(strokes, original) {
  const bounds = paths => {
    const points = paths.flatMap(stroke => stroke.points);
    const axes = [0, 1].map(axis => points.map(point => point[axis]));
    return axes.map(values => [Math.min(...values), Math.max(...values)]);
  };
  const from = bounds(strokes), to = bounds(original);
  return strokes.map(stroke => ({ points: stroke.points.map(point => point.map((value, axis) => {
    const [low, high] = from[axis], [targetLow, targetHigh] = to[axis];
    return targetLow + (value - low) * (targetHigh - targetLow) / (high - low);
  })) }));
}

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
 const base = g.character.normalize('NFD')[0];
 const variants = [g.strokes];
 for (const form of katakanaVariants[g.character] ?? kanaVariants[base] ?? []) {
   const body = parse(form), canonicalBody = g.strokes.slice(0, body.length);
   variants.push([...fitToBounds(body, canonicalBody), ...g.strokes.slice(body.length)]);
 }
 if (g.character === 'ヒ') {
   const [first, ...remaining] = g.strokes;
   variants.push([{ ...first, points: first.points.toReversed() }, ...remaining]);
 }
 return {code:g.character.codePointAt(0),source:1,variants};});
for(const [c,s] of Object.entries(latin)) {
  const variants = [parse(s)];
  if (doubleStorey[c]) variants.push(parse(doubleStorey[c]));
  for (const form of latinPrint[c] ?? []) variants.push(parse(form));
  entries.push({code:c.codePointAt(0),source:2,variants});
}
entries.sort((a,b)=>a.code-b.code);
if(hash(JSON.stringify(inputs))!=='01a63c4a0da45507a9580e111bd54954ff848801f838fe33e4d198c97b37afcc')throw Error('Input JSON differs from the pinned upstream commit');
if(entries.length!==238||new Set(entries.map(e=>e.code)).size!==238)throw Error('Coverage');
const bodies=entries.map(e=>{
 const a=[e.variants.length,0];
 for(const variant of e.variants) {
   a.push(variant.length,0);
   for(const s of variant) {
     const pts=resample(s.points);
     a.push(s.isCurl?1:0,0,pts.length,0);
     for(const p of pts)for(const v of p){if(!Number.isFinite(v)||v<0||v>1)throw Error('Coordinate '+e.code+' '+v);const n=Math.round(v*65535);a.push(n&255,n>>8);}
   }
 }
 return Buffer.from(a);
});
const total=16+entries.length*16+bodies.reduce((n,b)=>n+b.length,0), data=Buffer.alloc(total);
data.write('AWSTREF2');data.writeUInt32LE(entries.length,8);data.writeUInt32LE(total,12);let offset=16+entries.length*16;
entries.forEach((e,i)=>{const k=16+i*16;data.writeUInt32LE(e.code,k);data.writeUInt32LE(offset,k+4);data.writeUInt32LE(bodies[i].length,k+8);data.writeUInt32LE(e.source,k+12);bodies[i].copy(data,offset);offset+=bodies[i].length;});
fs.writeFileSync(path.join(out,'StrokeReference.bin'),data);
const lines=[];for(let i=0;i<data.length;i+=24)lines.push('  '+Array.from(data.subarray(i,i+24),v=>'$'+v.toString(16).padStart(2,'0').toUpperCase()).join(',')+(i+24<data.length?',':''));
fs.writeFileSync(path.join(out,'StrokeReference.inc'),'// CC-BY-SA-3.0; generated by Tools/build_stroke_reference.mjs; see NOTICE.md\r\n'+lines.join('\r\n')+'\r\n');
fs.writeFileSync(path.join(out,'StrokeReferenceSize.inc'),String(data.length-1)+'\r\n');
const alternateCharacters = entries.filter(entry => entry.variants.length>1).map(entry => String.fromCodePoint(entry.code));
fs.writeFileSync(path.join(out,'Manifest.json'),JSON.stringify({format:'AWSTREF2',license:'CC-BY-SA-3.0',kana:176,latin:62,alternateCharacters,bytes:total,sha256:hash(data),upstream:{repository:'https://github.com/karimghezali/fude-kana-data',commit:'ab69a27e2f5a5125ac89b5f13a1b0f0e318d5319',archiveSHA256:'c2aa4c0165bd76933c0468073755e252e279d1aa93fe0b32e2a3471e33fb823e'},inputs},null,2)+'\n');
console.log(JSON.stringify({characters:entries.length,bytes:total,sha256:hash(data)}));

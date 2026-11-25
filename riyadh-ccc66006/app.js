/* جولة مقترح العيادات: ثنائية اللغة */
const $=id=>document.getElementById(id);
let lang='ar';
try{const q=new URLSearchParams(location.search).get('lang');const s=localStorage.getItem('rh_lang');if(q==='en'||q==='ar')lang=q;else if(s==='en'||s==='ar')lang=s}catch(e){}
const t=o=>o[lang];
const rtl=()=>lang==='ar';
const fmt=n=>Math.round(n).toLocaleString('en-US');
const bw=n=>'⁦'+n+'⁩';
const reduce=()=>matchMedia('(prefers-reduced-motion: reduce)').matches;
const esc=s=>String(s).replace(/[&<>"]/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[m]));
let cur=1;

/* ---------- static text ---------- */
function applyStatic(){
  document.documentElement.lang=lang;document.documentElement.dir=rtl()?'rtl':'ltr';
  document.title=t(UI.title);
  document.querySelectorAll('[data-i]').forEach(e=>{const v=UI[e.dataset.i];if(!v)return;if(e.hasAttribute('data-h'))e.innerHTML=v[lang];else e.textContent=v[lang]});
  document.querySelectorAll('[data-ia]').forEach(e=>{const v=UI[e.dataset.ia];if(v)e.setAttribute('aria-label',v[lang])});
  document.querySelectorAll('[data-ial]').forEach(e=>{const v=UI[e.dataset.ial];if(v)e.setAttribute('alt',v[lang])});
  document.querySelectorAll('#lang button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.l===lang)));
  const nx=(n)=>t(UI.next)+': '+t(UI.steps[n]),bk=(n)=>t(UI.prev)+': '+t(UI.steps[n]);
  $('to3').textContent=nx(2);$('back3').textContent=bk(1);$('to4').textContent=nx(3);$('back4').textContent=bk(2);$('to5').textContent=nx(4);
  const v=$('vid'),s=$('snd');s.textContent=v.muted?t(UI.sndOn):t(UI.sndOff);
}
function buildNav(){
  const st=$('steps');st.innerHTML='';
  UI.steps.forEach((s,i)=>{const b=document.createElement('button');b.className='step';b.textContent=t(s);b.setAttribute('aria-current',String(i+1===cur));b.onclick=()=>go(i+1);st.appendChild(b)});
}
function setLang(l){
  lang=l;try{localStorage.setItem('rh_lang',l)}catch(e){}
  applyStatic();buildNav();buildP2();buildPlan();buildP4();buildFilm();buildRoad();checkVoice();
}
document.querySelectorAll('#lang button').forEach(b=>b.onclick=()=>{if(b.dataset.l!==lang)setLang(b.dataset.l)});

/* ---------- routing ---------- */
const pages=[...document.querySelectorAll('.page')];
function go(n){
  const prev=cur;cur=n;
  pages.forEach((p,i)=>p.classList.toggle('on',i+1===n));
  $('nav').classList.toggle('dark',n===1);
  document.querySelectorAll('#steps .step').forEach((b,i)=>b.setAttribute('aria-current',String(i+1===n)));
  const cb=document.querySelector('#steps .step[aria-current=true]');if(cb&&cb.scrollIntoView)cb.scrollIntoView({inline:'center',block:'nearest'});
  const v=$('vid');if(n===1){v.play().catch(()=>{})}else v.pause();
  if(n===2)requestAnimationFrame(()=>{sizeCv();draw(true)});
  if(n===5)enterFilm();else if(prev===5)leaveFilm();
  pages[n-1].scrollTop=0;
  try{history.replaceState(null,'','#p'+n+(lang==='en'?'':''))}catch(e){}
}
document.addEventListener('click',e=>{const x=e.target.closest('[data-go]');if(x)go(+x.dataset.go)});
document.addEventListener('keydown',e=>{
  if(/^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName)||e.target.isContentEditable)return;
  if(e.key!=='ArrowLeft'&&e.key!=='ArrowRight')return;
  const fwd=(e.key==='ArrowLeft')===rtl();   // اتجاه التقدم يتبع اتجاه اللغة
  if(cur===5){e.preventDefault();chapterStep(fwd?1:-1);return}
  if(fwd&&cur<6)go(cur+1);else if(!fwd&&cur>1)go(cur-1);
});
$('snd').onclick=()=>{const v=$('vid');v.muted=!v.muted;$('snd').setAttribute('aria-pressed',String(!v.muted));$('snd').textContent=v.muted?t(UI.sndOn):t(UI.sndOff);v.play().catch(()=>{})};

/* ---------- p2: market size ---------- */
let scen=1,cl='sp',focus='dld',share=2,dots=[],base=801500;const BASE0=801500;
const seg=$('seg'),doms=$('doms'),clinEl=$('clin'),detail=$('detail');
const cnt=(d,s)=>{const r=d.r[s];return r==null?null:base*BANDS[d.b].w*r/100};
const R100=n=>fmt(Math.round(n/100)*100),R10=n=>fmt(Math.round(n/10)*10);
function buildP2(){
  seg.innerHTML='';clinEl.innerHTML='';doms.innerHTML='';
  UI.scen.forEach((s,i)=>{const b=document.createElement('button');b.textContent=t(s);b.setAttribute('aria-pressed',String(i===scen));b.onclick=()=>{scen=i;render(true)};seg.appendChild(b)});
  CLIN.forEach(c=>{const b=document.createElement('button');b.textContent=t(c.n);b.setAttribute('aria-pressed','false');
    b.onclick=()=>{cl=c.k;focus=DOMS.find(d=>d.cl===c.k).k;render(true)};clinEl.appendChild(b);c.el=b});
  DOMS.forEach(d=>{d.c=CLIN.find(c=>c.k===d.cl).c;const b=document.createElement('button');b.className='dom';b.type='button';b.style.setProperty('--c',d.c);b.setAttribute('aria-pressed','false');
    b.innerHTML='<span class="dot"></span><span>'+esc(t(d.n))+'<small></small></span><span class="n"></span>';
    b.onclick=()=>{focus=d.k;render(true)};doms.appendChild(b);d.el=b});
  EXCL.forEach(x=>{const e=document.createElement('div');e.className='dom ex';
    e.innerHTML='<span class="dot"></span><span>'+esc(t(x.n))+'<small>'+esc(t(x.w))+'</small></span><span class="n">'+esc(t(UI.notCounted))+'</span>';doms.appendChild(e);x.el=e});
  render();
}
function detailHtml(d){
  const c=d.r[scen],n=cnt(d,scen),band=BANDS[d.b],vals=d.r.filter(v=>v!=null),hi=Math.max(...vals),lo=Math.min(...vals),top=hi*1.15;
  const pos=v=>(v/top*100).toFixed(1)+'%';
  const lab=UI.rl.map((x,i)=>'<span>'+esc(t(x))+': <b>'+(d.r[i]==null?'—':bw(d.r[i]+'%'))+'</b></span>').join('');
  let h='<h3>'+esc(t(d.n))+'</h3><div class="meta">'+esc(t(UI.band))+': '+esc(t(band.n))+' · '+(lang==='ar'?'نحو ':'about ')+R100(base*band.w)+' '+esc(t(UI.inCircle))+'</div>';
  if(c==null){
    const onlyHigh=d.r[2]!=null&&d.r[0]==null&&d.r[1]==null;
    h+='<p class="empty">'+t(UI.emptyA)+esc(t(UI.scen[scen]))+t(UI.emptyB)+(onlyHigh?t(UI.emptyHigh):t(UI.emptyOther))+'</p>';
  }else h+='<div class="big"><div><b>'+bw(c+'%')+'</b><span>'+esc(t(UI.rate))+' ('+esc(t(UI.scen[scen]))+')</span></div><div><b>'+R100(n)+'</b><span>'+esc(t(UI.kidsUnit))+'</span></div></div>';
  h+='<div class="rng" role="img" aria-label="'+lo+'%–'+hi+'%"><span class="fill" style="inset-inline-start:'+pos(lo)+';width:calc('+pos(hi)+' - '+pos(lo)+')"></span>'+(c!=null?'<span class="mk" style="inset-inline-start:'+pos(c)+'"></span>':'')+'</div><div class="rl">'+lab+'</div>';
  h+='<p class="basis-t">'+esc(t(d.t))+'</p><span class="flag '+d.f+'">'+esc(t(FLAGS[d.f]))+'</span>';
  return h}
const mq=matchMedia('(max-width:900px)');
function placeDetail(){const f=DOMS.find(d=>d.k===focus);if(mq.matches)f.el.after(detail);else document.querySelector('#p2 .mapbox').after(detail)}
mq.addEventListener('change',()=>placeDetail());
function render(anim){
  seg.querySelectorAll('button').forEach((b,i)=>b.setAttribute('aria-pressed',String(i===scen)));
  CLIN.forEach(c=>c.el.setAttribute('aria-pressed',String(c.k===cl)));
  DOMS.forEach(d=>{const on=d.cl===cl;d.el.hidden=!on;if(!on)return;
    const n=cnt(d,scen);d.el.setAttribute('aria-pressed',String(focus===d.k));
    d.el.querySelector('.n').textContent=n==null?'—':R100(n);
    d.el.querySelector('small').textContent=n==null?t(UI.unavail):t(BANDS[d.b].n)+' · '+bw(d.r[scen]+'%')});
  EXCL.forEach(x=>x.el.hidden=x.cl!==cl);
  const f=DOMS.find(d=>d.k===focus),fc=cnt(f,scen);
  detail.style.setProperty('--c',f.c);detail.innerHTML=detailHtml(f);placeDetail();
  $('kids').textContent=R100(base*BANDS[f.b].w);$('kidsl').textContent=t(BANDS[f.b].n)+' '+t(UI.inCircle);
  $('cap').textContent=fc==null?'—':R10(fc*share/100);
  $('capl').textContent=fc==null?t(UI.noVal):t(UI.capIn)+t(f.n)+(lang==='ar'?'»':'"');
  $('shv').textContent=bw(share+'%');$('ring').setAttribute('stroke-dasharray',(163*share/10)+' 163');
  const bt=$('bt');bt.innerHTML='';
  Object.values(BANDS).forEach(x=>{const tr=document.createElement('tr');tr.innerHTML='<td>'+esc(t(x.n))+'</td><td>'+bw((x.w*100).toFixed(1)+'%')+'</td><td>'+R100(base*x.w)+'</td>';bt.appendChild(tr)});
  draw(anim);
}
$('sh').oninput=e=>{share=+e.target.value;render()};
const baseIn=$('base'),baseErr=$('baseerr');
function setBase(raw){
  const s=String(raw).replace(/[٠-٩]/g,c=>'٠١٢٣٤٥٦٧٨٩'.indexOf(c)).replace(/[,،٬\s]/g,'');
  const v=/^\d+$/.test(s)?+s:NaN;
  if(!(v>=100000&&v<=3000000)){baseIn.setAttribute('aria-invalid','true');baseErr.hidden=false;baseErr.textContent=t(UI.baseErr)+fmt(base)+'.';return false}
  baseIn.removeAttribute('aria-invalid');baseErr.hidden=true;base=v;baseIn.value=fmt(v);render();return true}
baseIn.onchange=()=>setBase(baseIn.value);
baseIn.onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();setBase(baseIn.value)}};
$('basereset').onclick=()=>{baseIn.value=fmt(BASE0);setBase(BASE0)};
const cv=$('cv'),ctx=cv.getContext('2d');let t0=0,raf=0;
function sizeCv(){const r=cv.getBoundingClientRect(),k=devicePixelRatio||1;cv.width=r.width*k;cv.height=r.height*k}
function draw(anim){
  cancelAnimationFrame(raf);t0=performance.now();
  const d=DOMS.find(x=>x.k===focus),c=d?cnt(d,scen):null;
  const step=now=>{
    const p=(anim&&!reduce())?Math.min(1,(now-t0)/700):1;
    ctx.clearRect(0,0,cv.width,cv.height);
    if(c!=null&&dots.length){
      const W=cv.width,rad=W*0.0068,n=Math.min(dots.length,Math.max(1,Math.round(c/100))),off=DOMS.indexOf(d)*431;
      ctx.fillStyle=d.c;ctx.globalAlpha=.85;
      for(let i=0;i<Math.round(n*p);i++){const q=dots[(i+off)%dots.length];ctx.beginPath();ctx.arc(q[0]*W,q[1]*W,rad,0,6.283);ctx.fill();ctx.lineWidth=rad*.4;ctx.strokeStyle='#fff';ctx.stroke()}
      ctx.globalAlpha=1}
    if(p<1)raf=requestAnimationFrame(step)};
  raf=requestAnimationFrame(step)}
addEventListener('resize',()=>{sizeCv();draw()});

/* ---------- p3: floor plan ---------- */
const NS='http://www.w3.org/2000/svg',plan=$('plan'),CY=240;
function el(tag,a,txt){const e=document.createElementNS(NS,tag);for(const k in a)e.setAttribute(k,a[k]);if(txt!=null)e.textContent=txt;return e}
const RX=r=>rtl()?r.x:800-r.x-r.w;
let timers=[],curCase=-1;
const infoEl=$('info'),stepsEl=$('steps3'),replay=$('replay'),casesEl=$('cases');
function clearRoute(){timers.forEach(clearTimeout);timers=[];if(routeEl)routeEl.setAttribute('d','');Object.values(ROOMS).forEach(r=>{if(r.rect)r.rect.classList.remove('on');if(r.num)r.num.innerHTML=''})}
let routeEl=null;
function buildPlan(){
  clearRoute();plan.innerHTML='';
  plan.appendChild(el('rect',{x:0,y:210,width:800,height:60,class:'corr'}));
  plan.appendChild(el('line',{x1:20,y1:CY,x2:780,y2:CY,stroke:'#C9DCDA','stroke-width':2,'stroke-dasharray':'3 8'}));
  plan.appendChild(el('text',{x:rtl()?60:740,y:CY-8,'text-anchor':'middle',class:'lbl',style:'font-size:16px;fill:#56676B'},t(UI.corridor)));
  Object.keys(ROOMS).forEach(k=>{const r=ROOMS[k],x=RX(r),g=el('g',{});
    const rect=el('rect',{x,y:r.y,width:r.w,height:r.h,rx:20,class:'room'+(r.ext?' ext':''),tabindex:0,role:'button','aria-label':t(r.n),'data-k':k});
    g.appendChild(rect);
    const tx=el('text',{x:x+r.w/2,y:r.y+r.h/2+(r.img?36:6),'text-anchor':'middle',class:'lbl'},'');
    wrap(tx,t(r.n),r.w-16);g.appendChild(tx);
    if(r.img){const im=el('image',{x:x+r.w/2-28,y:r.y+r.h/2-58,width:56,height:56});im.setAttribute('href',r.img);g.appendChild(im)}
    r.num=el('g',{});g.appendChild(r.num);r.rect=rect;plan.appendChild(g);
    rect.addEventListener('click',()=>showRoom(k));rect.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();showRoom(k)}})});
  routeEl=el('path',{class:'route',d:''});plan.appendChild(routeEl);
  casesEl.innerHTML='';
  CASES.forEach((c,i)=>{const b=document.createElement('button');b.type='button';b.setAttribute('aria-pressed',String(i===curCase));b.innerHTML='<span></span><small></small>';b.querySelector('span').textContent=t(c.t);b.querySelector('small').textContent=t(c.s);b.onclick=()=>runCase(i);casesEl.appendChild(b)});
  if(curCase>=0)runCase(curCase,true);else{infoEl.innerHTML='<h3></h3><p></p>';infoEl.querySelector('h3').textContent=t(UI.p3pick);infoEl.querySelector('p').textContent=t(UI.p3pickT);stepsEl.innerHTML='';replay.hidden=true}
}
function wrap(tx,s,maxw){ // تقسيم تسمية الغرفة إلى سطرين عند الحاجة
  const words=s.split(' '),lim=Math.floor(maxw/9.5);let lines=[''],i=0;
  words.forEach(w=>{if((lines[i]+' '+w).trim().length>lim&&lines[i]){lines.push(w);i++}else lines[i]=(lines[i]+' '+w).trim()});
  const x=tx.getAttribute('x'),y=+tx.getAttribute('y');
  lines.forEach((l,j)=>{const sp=el('tspan',{x,dy:j===0?-(lines.length-1)*10:22},l);tx.appendChild(sp)});
}
function showRoom(k){clearRoute();curCase=-1;casesEl.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed','false'));stepsEl.innerHTML='';replay.hidden=true;ROOMS[k].rect.classList.add('on');infoEl.innerHTML='<h3></h3><p></p>';infoEl.querySelector('h3').textContent=t(ROOMS[k].n);infoEl.querySelector('p').textContent=t(ROOMS[k].d)}
function pathTo(keys){let d='';keys.forEach((k,i)=>{const r=ROOMS[k],cx=RX(r)+r.w/2,edge=r.y<CY?r.y+r.h:r.y;
  if(i===0)d+=`M${cx} ${edge} L${cx} ${CY}`;else d+=` L${cx} ${CY} L${cx} ${edge} L${cx} ${CY}`});return d}
function runCase(i,instant){
  clearRoute();curCase=i;const c=CASES[i];
  casesEl.querySelectorAll('button').forEach((b,j)=>b.setAttribute('aria-pressed',String(i===j)));
  infoEl.innerHTML='<h3></h3><p></p>';infoEl.querySelector('h3').textContent=t(c.t)+(rtl()?'، ':', ')+t(c.s);infoEl.querySelector('p').textContent=t(UI.p3journey);
  stepsEl.innerHTML='';c.st.forEach((s,j)=>{const li=document.createElement('li');li.innerHTML='<b></b><span></span>';li.querySelector('b').textContent=j+1;li.querySelector('span').textContent=t(s);li.style.opacity='.35';stepsEl.appendChild(li)});
  replay.hidden=false;
  c.r.forEach((k,j)=>{timers.push(setTimeout(()=>{
    const r=ROOMS[k],x=RX(r);r.rect.classList.add('on');
    const n=el('g',{});n.appendChild(el('circle',{cx:x+24,cy:r.y+24,r:17,fill:'#B5472B'}));n.appendChild(el('text',{x:x+24,y:r.y+30,'text-anchor':'middle',class:'num'},String(j+1)));r.num.appendChild(n);
    routeEl.setAttribute('d',pathTo(c.r.slice(0,j+1)));stepsEl.children[j].style.opacity='1'},(reduce()||instant)?0:j*850))});
}
replay.onclick=()=>{if(curCase>=0)runCase(curCase)};

/* ---------- p4: specialties ---------- */
let rc=0,fac=0;
const clin4=$('clin4'),panel=$('panel');
function kbTabs(container,sel,idxGet,idxSet){
  container.onkeydown=e=>{if(e.key!=='ArrowLeft'&&e.key!=='ArrowRight')return;e.preventDefault();e.stopPropagation();
    const fwd=(e.key==='ArrowLeft')===rtl(),n=container.querySelectorAll(sel).length;idxSet((idxGet()+(fwd?1:-1)+n)%n);
    const b=container.querySelectorAll(sel)[idxGet()];if(b)b.focus()}}
function buildP4(){
  clin4.innerHTML='';
  REC.forEach((r,i)=>{const b=document.createElement('button');b.className='ct';b.type='button';b.setAttribute('role','tab');b.style.setProperty('--c',r.c);b.setAttribute('aria-selected',String(i===rc));b.tabIndex=i===rc?0:-1;
    b.innerHTML='<img alt=""><span></span><small></small>';b.querySelector('img').src=r.img;b.querySelector('span').textContent=t(r.n);b.querySelector('small').textContent=t(r.age);
    b.onclick=()=>{rc=i;renderP4()};clin4.appendChild(b)});
  kbTabs(clin4,'.ct',()=>rc,i=>{rc=i;renderP4()});
  renderP4();
}
function renderP4(){
  clin4.querySelectorAll('.ct').forEach((b,i)=>{b.setAttribute('aria-selected',String(i===rc));b.tabIndex=i===rc?0:-1});
  const r=REC[rc];panel.style.setProperty('--c',r.c);
  const lists=[r.cond.map(x=>'<div class="it"><span>'+esc(t(x))+'</span></div>'),r.ass.map(a=>'<div class="it"><span>'+(a.n?'<bdi dir="auto">'+esc(a.n)+'</bdi><small>'+esc(a[lang])+'</small>':esc(a[lang]))+'</span></div>'),r.trt.map(x=>'<div class="it"><span>'+esc(t(x))+'</span></div>')];
  const cnts=[r.cond.length,r.ass.length,r.trt.length];
  panel.innerHTML='<div class="ph"><h3>'+esc(t(r.n))+'</h3><p class="tg">'+esc(t(r.tag))+'</p><span class="age">'+esc(t(r.age))+'</span></div><p class="cred">'+esc(t(UI.cred))+'</p><div class="facets" role="tablist" id="facets">'+UI.facets.map((f,i)=>'<button type="button" class="fc" role="tab" aria-selected="'+(i===fac)+'" tabindex="'+(i===fac?0:-1)+'"><b>'+cnts[i]+'</b><span>'+esc(t(f))+'</span></button>').join('')+'</div><div class="fb" role="tabpanel">'+lists[fac].join('')+'</div><div class="fol"><b>'+esc(t(UI.followT))+'</b>'+esc(t(r.fol))+'</div>';
  const fe=$('facets');fe.querySelectorAll('.fc').forEach((b,i)=>b.onclick=()=>{fac=i;renderP4();const nb=$('facets').querySelectorAll('.fc')[i];if(nb)nb.focus()});
  kbTabs(fe,'.fc',()=>fac,i=>{fac=i;renderP4()});
}

/* ---------- p5: film ---------- */
const film=$('film');let FC={starts:[0,12,24,36,48,60],total:72.5},ch=-1,voiceAvail=false,voiceOn=true,ccOn=true,holding=false,ended=false;
const voice=new Audio();
(window.__CH?Promise.resolve(window.__CH):fetch('chapters.json').then(r=>r.json())).then(j=>{FC=j;updateBars()}).catch(()=>{});
function buildFilm(){
  const bar=$('chbar');bar.innerHTML='';
  CHAP.forEach((c,i)=>{const b=document.createElement('button');b.className='chb';b.type='button';b.setAttribute('role','tab');b.setAttribute('aria-label',t(c.yr)+': '+t(c.h));b.setAttribute('aria-selected',String(i===ch));b.innerHTML='<span></span><i><u></u></i>';b.querySelector('span').textContent=t(c.yr);b.onclick=()=>seekChapter(i);bar.appendChild(b)});
  kbTabs(bar,'.chb',()=>Math.max(ch,0),i=>seekChapter(i));
  $('cc5').textContent=ccOn?t(UI.capOn):t(UI.capOff);
  $('vo5').textContent=voiceOn?t(UI.voiceOn):t(UI.voiceOff);
  $('prv5').textContent=ch<=0?t(UI.prevPage):t(UI.prevCh);
  $('nxt5').textContent=ch>=CHAP.length-1?t(UI.nextPage):t(UI.nextCh);
  setPlayLabel();
  if(ch>=0)showChapter(ch,false);else{$('cap5').textContent='';$('ov').innerHTML=''}
  updateBars();
}
function ovHtml(c){
  let h='<div class="yr">'+esc(t(c.yr))+'</div><h3>'+esc(t(c.h))+'</h3>';
  if(c.stats)h+='<div class="x">'+c.stats.map(s=>'<div class="s"><b>'+s.b+'</b><span>'+esc(t(UI[s.u]))+'</span></div>').join('')+'</div>';
  if(c.chips)h+='<div class="x">'+c.chips.map(s=>'<span class="c">'+esc(t(s))+'</span>').join('')+(c.prop?'<span class="p">'+esc(t(UI.proposed))+'</span>':'')+'</div>';
  return h}
function showChapter(i,animate){
  const c=CHAP[i],ov=$('ov');ov.innerHTML=ovHtml(c);
  if(animate&&!reduce()){ov.classList.remove('sw');void ov.offsetWidth;ov.classList.add('sw')}
  $('cap5').textContent=ccOn?t(c.sc):'';
  document.querySelectorAll('#chbar .chb').forEach((b,j)=>b.setAttribute('aria-selected',String(j===i)));
  $('prv5').textContent=i<=0?t(UI.prevPage):t(UI.prevCh);
  $('nxt5').textContent=i>=CHAP.length-1?t(UI.nextPage):t(UI.nextCh);
}
function chapterAt(tm){let k=0;FC.starts.forEach((s,i)=>{if(tm>=s-0.01)k=i});return k}
function updateBars(){
  const tm=film.currentTime||0;
  document.querySelectorAll('#chbar .chb u').forEach((u,k)=>{const s=FC.starts[k],e=FC.starts[k+1]??FC.total;u.style.width=Math.max(0,Math.min(1,(tm-s)/(e-s)))*100+'%'})}
function startVoice(i){
  voice.pause();holding=false;
  if(voiceAvail&&voiceOn){voice.src='audio/s'+(i+1)+(lang==='en'?'_en':'')+'.mp3';voice.currentTime=0;voice.play().catch(()=>{})}
}
function tick(){
  if(cur!==5)return;
  const tm=film.currentTime,k=chapterAt(tm);
  if(k!==ch){ch=k;showChapter(k,true);startVoice(k)}
  // إن كان التعليق الصوتي أطول من الفصل ننتظر نهايته قبل الانتقال
  const nextStart=FC.starts[ch+1];
  if(voiceAvail&&voiceOn&&!voice.paused&&!voice.ended&&nextStart!=null&&tm>=nextStart-0.15&&!holding){holding=true;film.pause()}
  updateBars();
  if(!film.paused)requestAnimationFrame(tick)}
voice.onended=()=>{if(holding){holding=false;film.play().catch(()=>{})}};
film.addEventListener('play',()=>{ended=false;setPlayLabel();requestAnimationFrame(tick)});
film.addEventListener('pause',()=>{setPlayLabel()});
film.addEventListener('ended',()=>{ended=true;setPlayLabel();updateBars()});
film.addEventListener('seeked',()=>{if(cur===5){const k=chapterAt(film.currentTime);if(k!==ch){ch=k;showChapter(k,true);startVoice(k)}updateBars()}});
function setPlayLabel(){const b=$('play5');b.textContent=ended?t(UI.replay):(film.paused?t(UI.play):t(UI.pause))}
function enterFilm(){
  ended=false;ch=-1;film.currentTime=0;showChapter(0,false);ch=0;
  if(!reduce())film.play().catch(()=>{});else setPlayLabel();
  startVoice(0);updateBars()}
function leaveFilm(){film.pause();voice.pause();holding=false}
function seekChapter(i){ended=false;film.currentTime=FC.starts[i]+0.05;ch=i;showChapter(i,true);startVoice(i);updateBars();if(film.paused&&!reduce())film.play().catch(()=>{})}
function chapterStep(d){
  const i=Math.max(ch,0)+d;
  if(i<0){go(4);return}
  if(i>=CHAP.length){go(6);return}
  seekChapter(i)}
$('prv5').onclick=()=>chapterStep(-1);
$('nxt5').onclick=()=>chapterStep(1);
$('play5').onclick=()=>{if(ended){seekChapter(0);return}if(film.paused){film.play().catch(()=>{});if(holding&&voice.paused)voice.play().catch(()=>{})}else{film.pause();voice.pause()}};
$('cc5').onclick=()=>{ccOn=!ccOn;$('cc5').setAttribute('aria-pressed',String(ccOn));$('cc5').textContent=ccOn?t(UI.capOn):t(UI.capOff);if(ch>=0)$('cap5').textContent=ccOn?t(CHAP[ch].sc):''};
$('vo5').onclick=()=>{voiceOn=!voiceOn;$('vo5').setAttribute('aria-pressed',String(voiceOn));$('vo5').textContent=voiceOn?t(UI.voiceOn):t(UI.voiceOff);if(!voiceOn){voice.pause();if(holding){holding=false;film.play().catch(()=>{})}}else if(ch>=0)startVoice(ch)};
function checkVoice(){
  const sfx=lang==='en'?'_en':'';
  Promise.all(CHAP.map((c,i)=>fetch('audio/s'+(i+1)+sfx+'.mp3',{method:'HEAD'}).then(r=>r.ok).catch(()=>false))).then(a=>{voiceAvail=a.some(Boolean);$('vo5').hidden=!voiceAvail})}
document.addEventListener('keydown',e=>{if(cur===5&&e.code==='Space'&&!/^(BUTTON|INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName)){e.preventDefault();$('play5').click()}});

/* ---------- p6: roadmap ---------- */
let roadSt={};try{roadSt=JSON.parse(localStorage.getItem('rh_road')||'{}')}catch(e){}
const saveRoad=()=>{try{localStorage.setItem('rh_road',JSON.stringify(roadSt))}catch(e){}};
function buildRoad(){
  const r=$('road');r.innerHTML='';
  ROAD.forEach((s,i)=>{const li=document.createElement('li');
    li.innerHTML='<div class="rh"><b></b><h3></h3></div><p></p><div class="own"></div><label><span class="tl"></span><input type="text" autocomplete="off"></label><label><span class="nl"></span><textarea></textarea></label>';
    li.querySelector('b').textContent=i+1;li.querySelector('h3').textContent=t(s.t);li.querySelector('p').textContent=t(s.d);li.querySelector('.own').textContent=t(UI.own)+t(s.o);
    li.querySelector('.tl').textContent=t(UI.timeLbl);li.querySelector('.nl').textContent=t(UI.noteLbl);
    const inp=li.querySelector('input'),ta=li.querySelector('textarea');inp.placeholder=t(UI.timePh);ta.placeholder=t(UI.notePh);
    inp.value=roadSt['t'+i]||'';ta.value=roadSt['n'+i]||'';
    inp.oninput=()=>{roadSt['t'+i]=inp.value;saveRoad()};ta.oninput=()=>{roadSt['n'+i]=ta.value;saveRoad()};
    r.appendChild(li)})}

/* ---------- init ---------- */
(window.__DOTS?Promise.resolve(window.__DOTS):fetch('dots.json').then(r=>r.json())).then(j=>{dots=j;sizeCv();draw()}).catch(()=>{});
setLang(lang);
const hm=location.hash.match(/^#p([1-6])$/);
if(hm)go(+hm[1]);else{$('nav').classList.add('dark');document.querySelectorAll('#steps .step')[0].setAttribute('aria-current','true')}

'use strict';
const DEFAULT=[2,0,1,3,8,9,6,7,11,10,4,5];
const ACTIONS=[
 {key:'B',name:'East · B',desc:'Right face button · Use power-up in Crash.',x:595,y:224,side:'right',row:281},
 {key:'A',name:'South · A',desc:'Bottom face button · Accelerate in Crash.',x:559,y:259,side:'right',row:345},
 {key:'Y',name:'North · Y',desc:'Top face button · Map or speedometer in Crash.',x:559,y:189,side:'right',row:217},
 {key:'X',name:'West · X',desc:'Left face button · Brake in Crash.',x:524,y:224,side:'right',row:409},
 {key:'L3',name:'Left stick click',desc:'Press the left analog stick. This does not change steering.',x:320,y:223,side:'left',row:350,stick:true},
 {key:'R3',name:'Right stick click',desc:'Press the right analog stick. This leaves stick movement unchanged.',x:490,y:303,side:'left',row:410,stick:true},
 {key:'LB',name:'Left bumper',desc:'The Xbox left shoulder button.',x:316,y:146,side:'left',row:151,shoulder:true},
 {key:'RB',name:'Right bumper',desc:'The Xbox right shoulder button.',x:551,y:146,side:'right',row:89,shoulder:true},
 {key:'LT',name:'Left trigger',desc:'Assign a physical button to fully press the left trigger.',x:316,y:110,side:'left',row:89,shoulder:true},
 {key:'RT',name:'Right trigger',desc:'Assign a physical button to fully press the right trigger.',x:551,y:110,side:'right',row:27,shoulder:true},
 {key:'☰',name:'Start / Menu',desc:'The game’s menu or start button.',x:471,y:205,side:'right',row:153,small:true},
 {key:'▣',name:'Back / View',desc:'The game’s view or back button.',x:394,y:205,side:'left',row:215,small:true}
];
let maps=[DEFAULT.slice(),DEFAULT.slice()],saved=clone(maps),player=0,selected=1,listening=false,connected=false,history=[],saving=false;
let backend=0;
let live=[false,false];
let bits=[0,0],axes=[[128,128,128,128],[128,128,128,128]],hats=[15,15];
const $=id=>document.getElementById(id);
function clone(x){return JSON.parse(JSON.stringify(x));}
function native(payload){window.webkit?.messageHandlers?.mapper?.postMessage(payload);}
function dirty(){return JSON.stringify(maps)!==JSON.stringify(saved);}
function feedback(message,kind=''){ $('feedback').textContent=message;$('feedback').className=kind; }
function physical(i){return 'Button '+(i+1);}
function bound(target,p=player){return maps[p].flatMap((v,i)=>v===target?[i]:[]);}
function svg(tag,attrs,parent){const e=document.createElementNS('http://www.w3.org/2000/svg',tag);for(const [k,v]of Object.entries(attrs))e.setAttribute(k,v);parent.appendChild(e);return e;}
function text(parent,x,y,value,cls){const e=svg('text',{x,y,class:cls},parent);e.textContent=value;return e;}
function activate(e,fn){e.addEventListener('click',fn);e.addEventListener('keydown',event=>{if(event.key==='Enter'||event.key===' '){event.preventDefault();fn();}});}
const controls=[],callouts=[],wires=[],labels=[];
ACTIONS.forEach((a,i)=>{
 const endpoint=a.side==='left'?197:663,sign=a.side==='left'?-1:1;
 // Lines are routed around controls, ending at a consistent label column.
 const elbow=(a.side==='left'?218:642);
 let path=`M${a.x},${a.y} H${elbow} V${a.row+15} H${endpoint}`;
 if(i===5)path=`M490,336 V398 H218 V425 H197`;
 if(i===3)path=`M524,242 V375 H642 V424 H663`;
 wires[i]=svg('path',{d:path,class:'wire'},$('wires'));
 const g=svg('g',{class:'control','data-action':i,role:'button',tabindex:0,'aria-label':a.name+' ('+a.key+')'},$('controls'));controls.push(g);
 if(a.shoulder)svg('rect',{x:a.x-35,y:a.y-13,width:70,height:26,rx:9,class:'surface'},g);
 else svg('circle',{cx:a.x,cy:a.y,r:a.stick?19:a.small?11:16,class:'surface'},g);
 text(g,a.x,a.y+.5,a.key,'');activate(g,()=>choose(i,true));
 const x=a.side==='left'?18:665;
 const label=svg('g',{class:'callout','data-action':i,role:'button',tabindex:0,'aria-label':'Remap '+a.name},$('callouts'));callouts.push(label);
 svg('rect',{x,y:a.row-7,width:177,height:48,rx:7},label);
 text(label,x+9,a.row+10,a.name,'name');labels.push(text(label,x+9,a.row+28,'','binding'));
 activate(label,()=>choose(i,true));
});
function choose(i,arm){selected=i;listening=!!arm;render();if(arm)feedback(`Choose a physical button on Player ${player+1} for ${ACTIONS[i].name}.`);}
function checkpoint(){history.push(clone(maps));if(history.length>40)history.shift();}
function assign(raw){
 if(!Number.isInteger(raw)||raw<0||raw>=12)return;
 checkpoint();const old=maps[player][raw],previous=bound(selected);
 for(const i of previous)if(i!==raw)maps[player][i]=old;
 maps[player][raw]=selected;listening=false;
 feedback(`Player ${player+1}: ${physical(raw)} → ${ACTIONS[selected].name}. Save when ready.`,'toast');render();
}
function switchPlayer(p){player=p;listening=false;render();$('monitor').textContent=`Player ${p+1} selected. Press a button to identify it.`;feedback(`Player ${p+1} selected. Click a diagram button to remap it.`);}
function render(){
 const a=ACTIONS[selected],inputs=bound(selected),changed=dirty();
 $('liveLabel').textContent=live[player]?'LIVE INPUT':'WAITING FOR INPUT';document.querySelector('.live-pill').classList.toggle('idle',!live[player]);
 document.querySelectorAll('.player').forEach(e=>{const active=Number(e.dataset.player)===player;e.classList.toggle('active',active);e.setAttribute('aria-selected',active);});
 $('startOutput').textContent=backend===2?'Stop virtual controllers':backend===1?'Cancel start':'Start virtual controllers';$('startOutput').classList.toggle('active',backend===2);$('outputProfile').disabled=backend!==0;$('runtimeNote').textContent=backend===2?'Keep this app open. Saved changes apply immediately.':'One saved layout applies to Crash and compatible Mac games.';
 $('visualTitle').textContent=`Player ${player+1} · Game controls`;
 $('actionKey').textContent=a.key;$('actionName').textContent=a.title||a.name;$('actionDesc').textContent=a.desc;
 $('bindingLabel').textContent=`Player ${player+1} binding`;
 $('boundButton').textContent=inputs.length?inputs.map(physical).join(', '):'Unassigned';
 $('boundDetail').textContent=inputs.length?'Physical controller button':'Choose a button to enable this action';
 $('editor').classList.toggle('listening',listening);
 $('listenText').textContent=connected?`Press your chosen button on Player ${player+1}. Other player input is ignored.`:'Connect your Twin USB adapter, then press your chosen button.';
 $('change').textContent=listening?'Cancel listening':'Change button';
 $('unassign').disabled=listening||!inputs.length;$('save').disabled=!changed||saving;
 $('undo').disabled=!history.length||saving;$('changes').textContent=changed?'● Unsaved changes':'No unsaved changes';$('changes').style.color=changed?'#e9c47b':'';
 $('copy').textContent=`Copy Player ${player+1} → Player ${2-player}`;
 ACTIONS.forEach((a,i)=>{
  const sources=bound(i),pressed=sources.some(n=>bits[player]&(1<<n));
  controls[i].classList.toggle('selected',i===selected);controls[i].classList.toggle('pressed',pressed);
  callouts[i].classList.toggle('selected',i===selected);callouts[i].classList.toggle('pressed',pressed);wires[i].classList.toggle('selected',i===selected);
  labels[i].textContent=(sources.length?sources.map(physical).join(' + '):'Unassigned')+'  →  '+a.key;
 });
 const ax=axes[player];$('leftAxis').setAttribute('transform',`translate(${(ax[0]-128)/18} ${(ax[1]-128)/18})`);$('rightAxis').setAttribute('transform',`translate(${(ax[2]-128)/18} ${(ax[3]-128)/18})`);
 $('dpad').style.fill=hats[player]<8?'#63dec0':'';native({type:'dirty',value:changed});
}
function receiveNative(msg){
 if(msg.type==='inputHealth'){live=msg.live;render();return;}
 if(msg.type==='backend'){backend=msg.state;feedback(msg.message,backend===2?'toast':'');render();return;}
 if(msg.type==='load'){maps=clone(msg.maps);saved=clone(maps);history=[];setConnection(msg.connected);render();}
 if(msg.type==='connection')setConnection(msg.connected);
 if(msg.type==='input'){
  const p=msg.player;if(p!==0&&p!==1)return;
  bits[p]=msg.bits;axes[p]=msg.axes||axes[p];hats[p]=msg.hat??15;
  if(msg.edge){const raw=Array.from({length:12},(_,i)=>i).filter(i=>msg.edge&(1<<i));
   if(p===player){
    if(listening){if(raw.length===1)assign(raw[0]);else feedback('Press just one button at a time.');}
    const target=maps[p][raw[0]];
    $('monitor').textContent=`Player ${p+1} · ${raw.map(physical).join(' + ')} → ${target<0?'Unassigned':ACTIONS[target].name}`;
   }else if(listening){$('monitor').textContent=`That was Player ${p+1}. Waiting for Player ${player+1}…`;}
  }
  render();
 }
 if(msg.type==='saved'){saving=false;saved=clone(msg.maps||maps);if(!dirty())history=[];feedback(backend===2?'Both players saved for Crash and other games. Active virtual controllers updated.':'Both players saved for Crash and other games.','toast');render();}
 if(msg.type==='error'){saving=false;feedback(msg.message,'error');render();}
}
function setConnection(value){connected=!!value;$('connection').classList.toggle('connected',connected);$('connectionText').textContent=connected?'Twin USB connected · 2 controllers':'Twin USB not connected';if(!connected){live=[false,false];bits=[0,0];axes=[[128,128,128,128],[128,128,128,128]];hats=[15,15];}render();}
window.receiveNative=receiveNative;
document.querySelectorAll('.player').forEach(e=>e.onclick=()=>switchPlayer(Number(e.dataset.player)));
$('change').onclick=()=>{listening=!listening;render();};
$('unassign').onclick=()=>{checkpoint();for(const i of bound(selected))maps[player][i]=-1;feedback(`Player ${player+1}: ${ACTIONS[selected].name} unassigned.`);render();};
$('reset').onclick=()=>{checkpoint();maps[player]=DEFAULT.slice();listening=false;feedback(`Player ${player+1} defaults restored. Save to apply.`);render();};
$('copy').onclick=()=>{checkpoint();maps[1-player]=maps[player].slice();feedback(`Copied Player ${player+1} to Player ${2-player}. Save to apply.`,'toast');render();};
$('undo').onclick=()=>{if(history.length){maps=history.pop();listening=false;feedback('Last change undone.');render();}};
$('save').onclick=()=>{if(saving||!dirty())return;saving=true;listening=false;render();native({type:'save',maps:clone(maps)});};
$('startOutput').onclick=()=>{if(backend){native({type:'stop'});return;}if(dirty()){feedback('Save both players before starting.');return;}backend=1;render();native({type:'start',profile:$('outputProfile').value});};
document.addEventListener('keydown',e=>{if(e.key==='Escape'){listening=false;render();}if((e.metaKey||e.ctrlKey)&&e.key==='s'){e.preventDefault();$('save').click();}if((e.metaKey||e.ctrlKey)&&e.key==='z'){e.preventDefault();$('undo').click();}});
// Run inside WKWebView with --self-test-ui; no real configuration is written.
function runRegressionTests(){
 let checks=0;const assert=(v,m)=>{if(!v)throw Error(m);checks++;};
 receiveNative({type:'load',maps:[DEFAULT,DEFAULT],connected:true});
 choose(1,true);receiveNative({type:'input',player:1,bits:1,edge:1});assert(listening,'other player must not bind');assert(maps[0][0]===2,'other player changed P1');
 receiveNative({type:'input',player:0,bits:1,edge:1});assert(maps[0][0]===1&&maps[0][2]===2,'P1 swap');assert(maps[1][0]===2,'P2 independence');assert(!listening&&dirty(),'binding must complete');
 switchPlayer(1);choose(0,true);receiveNative({type:'input',player:1,bits:4,edge:4});assert(maps[1][2]===0&&maps[1][1]===1,'P2 swap');assert(maps[0][2]===2,'P1 preserved');
 $('unassign').click();assert(maps[1][2]===-1,'unassign');$('undo').click();assert(maps[1][2]===0,'undo');
 $('copy').click();assert(JSON.stringify(maps[0])===JSON.stringify(maps[1]),'copy');$('undo').click();
 $('reset').click();assert(JSON.stringify(maps[1])===JSON.stringify(DEFAULT),'reset selected');assert(maps[0][0]===1,'reset isolation');
 choose(3,true);receiveNative({type:'input',player:1,bits:3,edge:3});assert(listening,'multi press must not bind');switchPlayer(0);assert(!listening,'switch cancels listening');assert($('feedback').textContent.startsWith('Player 1 selected'),'switch updates player instruction');receiveNative({type:'inputHealth',live:[true,false]});assert($('liveLabel').textContent==='LIVE INPUT','live badge follows physical input');switchPlayer(1);assert($('liveLabel').textContent==='WAITING FOR INPUT','other player health independent');switchPlayer(0);
 setConnection(false);assert(bits.every(b=>b===0),'disconnect clears highlights');setConnection(true);
 for(let p=0;p<2;p++){switchPlayer(p);for(let target=0;target<12;target++){choose(target,true);assert(document.body.scrollHeight<=innerHeight,'listening layout '+target+' body='+document.body.scrollHeight+' viewport='+innerHeight+' edit='+$('editor').clientHeight+' aside='+document.querySelector('aside').clientHeight);assign((target+5)%12);assert(maps[p][(target+5)%12]===target,'all action targets');assert(new Set(maps[p]).size===12,'swap uniqueness');}}
 receiveNative({type:'saved'});assert(!dirty(),'save acknowledgment');assert(document.querySelectorAll('.mode').length===0,'one shared panel');
 receiveNative({type:'load',maps:clone(saved),connected:true});assert(!dirty(),'reload');
 assert($('startOutput').textContent==='Start virtual controllers','start state');receiveNative({type:'backend',state:2,message:'Test active'});assert($('startOutput').textContent==='Stop virtual controllers'&&$('outputProfile').disabled,'active state');receiveNative({type:'backend',state:0,message:'Test stopped'});
 assert(document.querySelectorAll('.control').length===12,'diagram controls');assert(document.querySelectorAll('.callout').length===12,'action callouts');
 const overflow=[...document.querySelectorAll('.workspace,.edit,.footer')].some(e=>e.scrollWidth>e.clientWidth+1);assert(!overflow,'layout overflow');assert(document.body.scrollHeight<=innerHeight,'footer must fit without scrolling');
 return `PASS ${checks} checks: both players, all 12 actions, swaps, isolation, unassign, undo, reset, copy, capture, disconnect, persistence state, layout.`;
}
render();

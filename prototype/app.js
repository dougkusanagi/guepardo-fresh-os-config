'use strict';
const $=s=>document.querySelector(s), $$=s=>[...document.querySelectorAll(s)];
const model=window.GuepardoModel, apps=model.initialApps(window.GUEPARDO_CATALOG), selected=new Set();
let filter={query:'',status:'all',profile:'all'},busy=false,detailId=null,toastTimer,previousFocus,cancelRequested=false;
const labels={installed:'Instalado',missing:'Não instalado',failed:'Falha na instalação',reboot:'Reinício pendente'};
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const icons={
 'Microsoft.PowerShell':['›_','#183e59','#8bcdf7'], 'Git.Git':['git','#482b25','#f68b6c'], 'guepardo.sloth-note':['S','#483b28','#edce8e'], 'Rustlang.Rustup':['R','#3f3029','#e8b596'], 'guepardo.dotagents':['✳','#333c2a','#d1f675'], 'guepardo.wsl2':['›_','#473127','#ec9b68'], 'Jellyfin.Server':['△','#392c48','#cf9dec'], 'GitHub.cli':['gh','#30343c','#d8e0eb'],'CoreyButler.NVMforWindows':['N','#283c2e','#92cb8f'], 'OpenAI.Codex':['✳','#2f3c35','#c7e4d3'], 'OpenAI.CodexCLI':['✳','#2f3c35','#c7e4d3']
};
function icon(app){const i=icons[app.id]||[app.name.slice(0,2),['#2c3943','#3e3443','#2e3d38','#3e3c2b'][app.order%4],'#d2dfd3'];return `<span class="app-icon" style="--icon-bg:${i[1]};--icon-color:${i[2]}">${esc(i[0])}</span>`;}
function badge(app){return `<span class="badge ${app.status}"><i></i>${labels[app.status]}</span>`;}
function notify(text){clearTimeout(toastTimer);$('#toast').textContent=text;$('#toast').hidden=false;toastTimer=setTimeout(()=>$('#toast').hidden=true,3500);}
function render(){
 const counts=model.stats(apps),visible=model.filterApps(apps,filter);
 const bulk=model.selectionState(visible,selected);
 $('#select-visible').checked=bulk.checked;$('#select-visible').indeterminate=bulk.indeterminate;
 $('#select-visible').disabled=busy||bulk.eligible.length===0;
 $('#bulk-label').textContent=`Selecionar todos desta lista (${bulk.eligible.length})`;
 $('#select-catalog').hidden=!apps.some(a=>model.selectable(a)&&!visible.some(v=>v.id===a.id));
 $('#select-catalog').disabled=busy;$('#retry-failed').hidden=!apps.some(a=>a.status==='failed');$('#retry-failed').disabled=busy;
 $('#selection-scope').textContent='Inclui apenas não instalados e falhas. Instalados e reinícios pendentes são preservados.';
 $('#tab-attention').textContent=counts.attention;
 $('#result-caption').textContent=`${visible.length} ${visible.length===1?"aplicativo":"aplicativos"} · ${counts.installed} instalados`;
 $('#cards').innerHTML=visible.map(a=>`<article class="app-row ${selected.has(a.id)?'selected':''}" data-id="${esc(a.id)}">${!['installed','reboot'].includes(a.status)?`<input type="checkbox" class="row-check" aria-label="Selecionar ${esc(a.name)}" data-select="${esc(a.id)}" ${selected.has(a.id)?'checked':''} ${busy?'disabled':''}>`:`<span class="row-mark" aria-label="${labels[a.status]}">${a.status==='installed'?'✓':'◷'}</span>`}${icon(a)}<button class="app-info" data-details="${esc(a.id)}" aria-label="Ver detalhes de ${esc(a.name)}"><strong>${esc(a.name)}</strong><span>${esc(a.category)}</span></button>${badge(a)}<button class="row-detail" data-details="${esc(a.id)}" aria-label="Detalhes de ${esc(a.name)}">›</button></article>`).join('');
 $('#empty').hidden=visible.length!==0;$('#selection').hidden=selected.size===0||busy;$('#selected-count').textContent=selected.size+(selected.size===1?' aplicativo selecionado':' aplicativos selecionados');
 const plan=model.installationPlan(apps,[...selected]),extra=plan.filter(a=>!selected.has(a.id)).length,hidden=[...selected].filter(id=>!visible.some(a=>a.id===id)).length;
 $('#selection-note').textContent=[hidden?`${hidden} fora do filtro atual`:null,extra?`${extra} dependência(s) incluída(s)`:null].filter(Boolean).join(' · ')||'Pronto para instalar.';
 $('#install').innerHTML=`Instalar ${plan.length} ${plan.length===1?'aplicativo':'aplicativos'} <span>→</span>`;
 $$('.tabs button').forEach(b=>b.classList.toggle('active',b.dataset.filter===filter.status));
 $$('.nav').forEach(b=>b.classList.toggle('active',b.dataset.view===filter.status&&filter.profile==='all'));
 $$('.profile-nav button').forEach(b=>b.classList.toggle('active',b.dataset.profile===filter.profile));
 $('#category').value=filter.profile;
}
function setFilter(values){Object.assign(filter,values);render();}
function closeDetails(){ $('#details').hidden=true;$('#overlay').hidden=true;detailId=null;previousFocus?.focus();}
function showDetails(id){
 const a=apps.find(a=>a.id===id);if(!a)return;previousFocus=document.activeElement;detailId=id;
 const warnings={ 'guepardo.sloth-note':'A última tentativa não conseguiu inicializar o ambiente MSVC. A instalação precisa das ferramentas de compilação C++ do Visual Studio.', 'guepardo.dotagents':'A última sincronização encontrou uma restrição ao criar links simbólicos. Verifique o Modo de Desenvolvedor do Windows.', 'guepardo.wsl2':'O recurso está aguardando reinicialização neste cenário de demonstração. Seus aplicativos Windows continuam disponíveis.' };
 $('#details').innerHTML=`<button class="close" aria-label="Fechar detalhes">×</button><div class="eyebrow">SUA BIBLIOTECA / APLICATIVO</div>${icon(a)}<h2 id="detail-title">${esc(a.name)}</h2>${badge(a)}<p>${esc(a.description)}</p><dl><div><dt>Categoria</dt><dd>${esc(a.category)}</dd></div><div><dt>Instalação via</dt><dd>${esc(a.provider)}</dd></div><div><dt>Identificador</dt><dd>${esc(a.id)}</dd></div><div><dt>Versão desejada</dt><dd>Estável mais recente</dd></div><div><dt>Plataforma</dt><dd>Windows</dd></div><div><dt>Dependências</dt><dd>${a.dependencies.length?a.dependencies.map(id=>esc(apps.find(x=>x.id===id)?.name||id)).join(', '):'Nenhuma'}</dd></div></dl>${['failed','reboot'].includes(a.status)?`<div class="detail-warning">${esc(warnings[a.id]||'Esta instalação precisa de atenção.')}</div><button class="outline" id="show-log">Ver diagnóstico de exemplo ↗</button><pre class="log-box" id="detail-log" hidden></pre>`:''}${a.status!=='installed'?`<button class="primary" id="detail-install" ${busy?'disabled':''}>${a.status==='failed'?'Tentar novamente':a.status==='reboot'?'Conferir após reiniciar':'Adicionar à instalação'} <span>→</span></button>`:'<div class="detail-warning">✓ Disponível no seu ambiente de demonstração.</div>'}`;
 $('#details').hidden=false;$('#overlay').hidden=false;$('#details .close').onclick=closeDetails;
 $('#details .close').focus();
 if($('#show-log'))$('#show-log').onclick=()=>{const log=$('#detail-log');log.hidden=!log.hidden;log.textContent=`[demo] ${a.id}\n[status] ${labels[a.status]}\n[diagnóstico] ${warnings[a.id]}\n\nEste registro é ilustrativo; não foi lido do sistema.`;};
 if($('#detail-install'))$('#detail-install').onclick=()=>{if(a.status==='reboot'){notify('Na versão final, o estado será conferido após reiniciar o Windows.');return;}selected.add(a.id);closeDetails();render();};
}
async function install(){
 if(busy||!selected.size)return;const plan=model.installationPlan(apps,[...selected]);if(!plan.length)return;
 busy=true;cancelRequested=false;closeDetails();$('#activity').hidden=false;$('#finish').hidden=true;$('#cancel-install').hidden=false;$('#cancel-install').disabled=false;$('#cancel-install').textContent='Cancelar restantes';$('#close-activity').disabled=true;$('#activity-title').textContent='Preparando seu ambiente';$('#install-progress').style.width='0%';render();
 const rows=plan.map(a=>({app:a,state:'Na fila'}));
 function progress(){ $('#activity-items').innerHTML=rows.map(r=>`<div class="activity-row"><span>${esc(r.app.name)}</span><span>${r.state}</span></div>`).join(''); }
 progress();
 for(let i=0;i<rows.length;i++){
   if(cancelRequested){rows.slice(i).forEach(r=>r.state='Cancelado');progress();break;}
   rows[i].state='Instalando…';progress();await new Promise(r=>setTimeout(r,850));
   rows[i].app.status=rows[i].app.id==='guepardo.wsl2'?'reboot':'installed';rows[i].state=rows[i].app.status==='reboot'?'Reinício pendente':'✓ Concluído';
   selected.delete(rows[i].app.id);
   $('#install-progress').style.width=Math.round((i+1)/rows.length*100)+'%';progress();render();
 }
 busy=false;$('#activity-title').textContent=cancelRequested?'Simulação interrompida':'Simulação concluída';$('#cancel-install').hidden=true;$('#close-activity').disabled=false;$('#finish').hidden=false;render();
}
$('#cards').addEventListener('click',e=>{const check=e.target.closest('[data-select]');if(check){e.stopPropagation();const id=check.dataset.select;if(check.checked)selected.add(id);else selected.delete(id);render();$(`[data-select="${CSS.escape(id)}"]`)?.focus();return;}const card=e.target.closest('[data-id]');if(card)showDetails(card.dataset.id);});
function replaceSelection(next){selected.clear();next.forEach(id=>selected.add(id));render();}
$('#select-visible').onchange=e=>replaceSelection(model.selectVisible(model.filterApps(apps,filter),selected,e.target.checked));
$('#select-catalog').onclick=()=>replaceSelection(model.selectVisible(apps,selected,true));
$('#retry-failed').onclick=()=>{replaceSelection(new Set(apps.filter(a=>a.status==='failed').map(a=>a.id)));notify('Falhas selecionadas. Revise e clique em instalar.');};
$('#cancel-install').onclick=()=>{cancelRequested=true;$('#cancel-install').disabled=true;$('#cancel-install').textContent='Finalizando o item atual…';};
$('#search').addEventListener('input',e=>setFilter({query:e.target.value}));
$('#category').onchange=e=>setFilter({profile:e.target.value});
$$('.tabs button').forEach(b=>b.onclick=()=>setFilter({status:b.dataset.filter}));
$$('.nav').forEach(b=>b.onclick=()=>{setFilter({status:b.dataset.view,profile:'all'});$('.library').scrollIntoView({behavior:'smooth',block:'start'});});
$$('[data-profile]').forEach(b=>b.onclick=()=>{setFilter({profile:b.dataset.profile,status:'all'});$('.library').scrollIntoView({behavior:'smooth',block:'start'});});
$('#clear-filters').onclick=()=>{$('#search').value='';setFilter({query:'',status:'all',profile:'all'});};
$('#clear-selection').onclick=()=>{selected.clear();render();};$('#install').onclick=install;
$('#overlay').onclick=closeDetails;$('#finish').onclick=$('#close-activity').onclick=()=>{if(!busy)$('#activity').hidden=true;};
$('#theme').onclick=()=>document.body.classList.toggle('light');
$('#reset').onclick=()=>{if(busy){notify('Aguarde a simulação terminar para restaurar.');return;}apps.splice(0,apps.length,...model.initialApps(window.GUEPARDO_CATALOG));selected.clear();$('#activity').hidden=true;closeDetails();render();notify('Demonstração restaurada.');};
$('#scan').onclick=async()=>{const b=$('#scan');b.disabled=true;b.querySelector('span').textContent='Verificando…';await new Promise(r=>setTimeout(r,1000));b.disabled=false;b.querySelector('span').textContent='Verificar aplicativos';render();notify('Catálogo de demonstração atualizado. Nenhuma leitura do sistema foi feita.');};
document.addEventListener('keydown',e=>{if(e.key==='Escape')closeDetails();if(e.key==='/'&&!['INPUT','TEXTAREA','SELECT'].includes(document.activeElement.tagName)&&$('#details').hidden){e.preventDefault();$('#search').focus();}if(e.key==='Tab'&&!$('#details').hidden){const focusables=[...$('#details').querySelectorAll('button:not(:disabled),[tabindex="0"]')];const first=focusables[0],last=focusables.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus();}}});
render();

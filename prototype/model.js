(function (root) {
  'use strict';
  const featured = ['Microsoft.PowerShell','Git.Git','guepardo.sloth-note','OpenAI.Codex','Rustlang.Rustup','guepardo.dotagents','guepardo.wsl2','Jellyfin.Server','CoreyButler.NVMforWindows'];
  const missing = ['Microsoft.PowerShell','Rustlang.Rustup','Jellyfin.Server','Valve.Steam','Docker.DockerDesktop','Obsidian.Obsidian','Warp.Warp','T3Tools.T3Code','RedHat.Podman-Desktop','guepardo.zapfast','guepardo.jellyfin-config'];
  const descriptions = {
    'Microsoft.PowerShell':'Um terminal poderoso. Automação e scripts com o PowerShell estável mais recente.',
    'Git.Git':'Cada mudança no seu lugar. Controle de versão para seus próximos projetos.',
    'guepardo.sloth-note':'Suas ideias merecem um lugar. Notas rápidas, organizadas e sempre por perto.',
    'guepardo.dotagents':'Seus agentes, em sintonia. Instale e sincronize suas configurações.',
    'guepardo.wsl2':'O melhor dos dois mundos. Ubuntu integrado ao seu ambiente Windows.',
    'Rustlang.Rustup':'Velocidade e confiança. Prepare rustc, Cargo e sua toolchain Rust.',
    'Jellyfin.Server':'Seus filmes, suas séries, seu servidor. Uma casa para sua biblioteca.',
    'GitHub.cli':'Issues, pull requests e repositórios. Seu GitHub direto no terminal.',
    'CoreyButler.NVMforWindows':'A versão certa para cada projeto. Gerencie seu ambiente Node.js.',
    'OpenAI.Codex':'Uma nova companhia para construir. Seu agente de programação no terminal.',
    'OpenAI.CodexCLI':'Uma nova companhia para construir. Seu agente de programação no terminal.'
  };
  const categoryNames={cli:'Terminal e ferramentas',dev:'Desenvolvimento',web:'Web e banco de dados',desktop:'Dia a dia',games:'Jogos e diversão',jellyfin:'Media center',wsl2:'WSL e Ubuntu'};
  function initialApps(catalog) {
    return catalog.filter(a=>a.windows).map((a,index)=>({
      id:a.id,name:a.id==='guepardo.wsl2'?'WSL + Ubuntu':a.id==='guepardo.sloth-note'?'Sloth Note':a.id==='Microsoft.PowerShell'?'PowerShell':a.name.replace(/ \(.*\)$/,''),
      profiles:a.profiles,dependencies:a.dependsOn,provider:a.windows.provider==='custom'?'Personalizado':a.windows.scoop?'Scoop':'Winget',
      status:['guepardo.sloth-note','guepardo.dotagents'].includes(a.id)?'failed':a.id==='guepardo.wsl2'?'reboot':missing.includes(a.id)?'missing':'installed',
      description:descriptions[a.id]||`Tudo pronto para usar ${a.name.replace(/ \(.*\)$/,'')}. Uma ferramenta a mais para deixar seu Windows do seu jeito.`,
      category:categoryNames[a.profiles[0]]||'Ferramentas',order:featured.includes(a.id)?featured.indexOf(a.id):featured.length+index
    })).sort((a,b)=>a.order-b.order);
  }
  function filterApps(apps,{query='',status='all',profile='all'}={}) {
    const normalize=s=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
    return apps.filter(a=>(profile==='all'||a.profiles.includes(profile))&&(status==='all'||(status==='attention'?['failed','reboot'].includes(a.status):status==='missing'?a.status!=='installed':a.status===status))&&normalize(a.name+' '+a.id+' '+a.category).includes(normalize(query)));
  }
  function stats(apps){return {total:apps.length,installed:apps.filter(a=>a.status==='installed').length,missing:apps.filter(a=>a.status==='missing').length,attention:apps.filter(a=>['failed','reboot'].includes(a.status)).length};}
  function installationPlan(apps,ids){
    const result=[],seen=new Set();
    function visit(id){if(seen.has(id))return;seen.add(id);const app=apps.find(a=>a.id===id);if(!app)return;app.dependencies.forEach(visit);if(app.status!=='installed')result.push(app);}
    ids.forEach(visit);return result;
  }
  function selectable(app) { return ['missing','failed'].includes(app.status); }
  function selectionState(visible,selected) {
    const eligible=visible.filter(selectable),count=eligible.filter(a=>selected.has(a.id)).length;
    return {eligible:eligible.map(a=>a.id),checked:eligible.length>0&&count===eligible.length,indeterminate:count>0&&count<eligible.length,count};
  }
  function selectVisible(visible,selected,checked) {
    const next=new Set(selected);
    visible.filter(selectable).forEach(a=>checked?next.add(a.id):next.delete(a.id));
    return next;
  }
  const api={initialApps,filterApps,stats,installationPlan,selectable,selectionState,selectVisible};
  if(typeof module!=='undefined')module.exports=api;else root.GuepardoModel=api;
})(typeof window==='undefined'?globalThis:window);

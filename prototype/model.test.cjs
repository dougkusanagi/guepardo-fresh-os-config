const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const m=require('./model.js');
const catalog=JSON.parse(fs.readFileSync(path.join(__dirname,'../catalog/apps.json'),'utf8')).apps;
test('catalog contains only Windows apps and stable PowerShell without WSL dependency',()=>{
 const apps=m.initialApps(catalog);assert.ok(apps.length>60);assert.ok(apps.find(a=>a.id==='Microsoft.PowerShell'));assert.deepEqual(apps.find(a=>a.id==='guepardo.wsl2').dependencies,[]);assert.equal(apps.find(a=>a.id==='guepardo.sloth-note').status,'failed');
});
test('filters combine search, category and status',()=>{
 const apps=m.initialApps(catalog);assert.equal(m.filterApps(apps,{query:'powershell',profile:'cli',status:'missing'}).length,1);assert.equal(m.filterApps(apps,{query:'powershell',profile:'wsl2'}).length,0);assert.ok(m.filterApps(apps,{status:'attention'}).every(a=>['failed','reboot'].includes(a.status)));assert.equal(m.filterApps(apps,{query:'zzzzzz'}).length,0);
});
test('summary accounts for every application',()=>{const apps=m.initialApps(catalog),s=m.stats(apps);assert.equal(s.total,s.installed+s.missing+s.attention);});
test('installation orders dependencies, deduplicates and skips installed apps',()=>{
 const apps=[{id:'a',dependencies:['b'],status:'missing'},{id:'b',dependencies:['c'],status:'failed'},{id:'c',dependencies:[],status:'installed'}];assert.deepEqual(m.installationPlan(apps,['a','b','a']).map(a=>a.id),['b','a']);assert.deepEqual(m.installationPlan(apps,['unknown']),[]);apps[0].status='installed';apps[1].status='installed';assert.deepEqual(m.installationPlan(apps,['a']),[]);
});
test('prototype catalog matches repository catalog',()=>{const vm=require('node:vm'),context={window:{}};vm.runInNewContext(fs.readFileSync(path.join(__dirname,'catalog.js'),'utf8'),context);assert.equal(JSON.stringify(context.window.GUEPARDO_CATALOG),JSON.stringify(catalog));});
test('bulk selection includes missing and failed, never installed or pending reboot',()=>{
 const apps=m.initialApps(catalog),selected=m.selectVisible(apps,new Set(),true);
 assert.ok(selected.size>1);assert.ok(selected.has('guepardo.sloth-note'));assert.ok(!selected.has('Git.Git'));assert.ok(!selected.has('guepardo.wsl2'));
 assert.equal(m.selectionState(apps,selected).checked,true);
 selected.delete('Microsoft.PowerShell');assert.equal(m.selectionState(apps,selected).indeterminate,true);
});
test('filtered bulk deselection preserves hidden selection and handles empty lists',()=>{
 const apps=m.initialApps(catalog),visible=m.filterApps(apps,{query:'powershell'}),initial=new Set(['guepardo.sloth-note']);
 const selected=m.selectVisible(visible,initial,true);assert.equal(selected.size,2);assert.equal(initial.size,1);
 assert.deepEqual([...m.selectVisible(visible,selected,false)],['guepardo.sloth-note']);
 assert.equal(m.selectionState([],selected).checked,false);assert.equal(m.selectionState([],selected).indeterminate,false);
 assert.equal(m.selectionState(apps.filter(a=>a.status==='installed'),selected).eligible.length,0);
});

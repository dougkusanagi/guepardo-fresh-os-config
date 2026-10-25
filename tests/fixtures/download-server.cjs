const http = require('node:http');
const fs = require('node:fs');
const payload = Buffer.alloc(131072, 71);
const counts = {}; let active = 0, peak = 0;
const server = http.createServer((req,res) => {
  const route=req.url.split('?')[0]; counts[req.url]=(counts[req.url]||0)+1;
  if(route==='/stats') { res.setHeader('Content-Type','application/json'); res.end(JSON.stringify({counts,peak})); return; }
  if(route==='/bad') { res.end('wrong content'); return; }
  if(route==='/delay') { active++; peak=Math.max(peak,active); setTimeout(()=>{active--;res.end(payload);},1500); return; }
  if(route==='/resume' && counts[req.url]===1) {
    res.writeHead(200,{'Content-Length':payload.length,'Accept-Ranges':'bytes'});
    res.write(payload.subarray(0,32768)); setTimeout(()=>res.destroy(),30); return;
  }
  const match=/^bytes=(\d+)-$/.exec(req.headers.range||'');
  if(match) {
    const start=Number(match[1]);
    res.writeHead(206,{'Content-Length':payload.length-start,'Content-Range':`bytes ${start}-${payload.length-1}/${payload.length}`,'Accept-Ranges':'bytes'});
    res.end(payload.subarray(start)); return;
  }
  res.writeHead(200,{'Content-Length':payload.length,'Accept-Ranges':'bytes'}); res.end(payload);
});
server.listen(0,'127.0.0.1',()=>fs.writeFileSync(process.argv[2],String(server.address().port)));

const http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const types={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8'};
const server=http.createServer((req,res)=>{
 let name;try{name=decodeURIComponent(new URL(req.url,'http://localhost').pathname);}catch{res.writeHead(400).end();return;}
 const target=path.resolve(__dirname,'.'+(name==='/'?'/index.html':name));
 if(!target.startsWith(__dirname+path.sep)){res.writeHead(403).end();return;}
 fs.readFile(target,(err,data)=>{if(err){res.writeHead(404).end('Not found');return;}res.writeHead(200,{'Content-Type':types[path.extname(target)]||'text/plain; charset=utf-8'});res.end(data);});
});
server.listen(4173,'127.0.0.1',()=>console.log('Local: http://127.0.0.1:4173'));

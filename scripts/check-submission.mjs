import { readdir, lstat, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
const excludedRoot = new Set(['.git', '.imd', '.agents', '.aws', '.codex']);
const reportPath = 'artifacts/submission-inventory.json';
const files=[];
async function walk(directory='') {
  for (const name of (await readdir(directory||'.')).sort()) {
    if(!directory&&excludedRoot.has(name))continue;
    const path=join(directory,name);
    if(path==='test/scratch'||path===reportPath)continue;
    if(['node_modules','.npm','.cache','cache','__pycache__','out','coverage'].includes(name)) {
      // Never traverse protected dependency folders. They must be excluded from Git.
      execFileSync('git',['check-ignore','--quiet',path],{env:{...process.env,GIT_OPTIONAL_LOCKS:'0'}});
      const tracked=execFileSync('git',['ls-files','--',path],{encoding:'utf8',env:{...process.env,GIT_OPTIONAL_LOCKS:'0'}});
      assert.equal(tracked.trim(),'',`Generated files are tracked: ${path}`);
      continue;
    }
    assert.ok(!['.git','.github'].includes(name),`Forbidden directory: ${path}`);
    assert.ok(!name.startsWith('.env')&&name!=='.gitmodules',`Forbidden configuration or submodule: ${path}`);
    assert.ok(!/\.(tgz|tar|zip|tar\.gz)$/.test(name),`Unnecessary archive: ${path}`);
    const info=await lstat(path);
    assert.ok(!info.isSymbolicLink(),`Unresolved symlink: ${path}`);
    if(info.isDirectory())await walk(path);
    else {
      const data=await readFile(path);
      files.push({path,bytes:data.length,sha256:createHash('sha256').update(data).digest('hex')});
    }
  }
}
await walk();
assert.ok((await readFile('.gitignore')).length<=512,'Ignore file exceeds its explicit path budget');
for(const file of files.filter(f=>f.path.startsWith('site/'))){
  const counterpart=files.find(f=>f.path==='dist/'+file.path.slice(5));
  assert.ok(counterpart,`Missing export: ${file.path}`);
  assert.equal(counterpart.sha256,file.sha256,`Stale export: ${file.path}`);
}
assert.equal(files.filter(f=>f.path.startsWith('dist/')).length,files.filter(f=>f.path.startsWith('site/')).length,'Extraneous export files');
const manifest=JSON.parse(await readFile('launch.json','utf8'));
assert.deepEqual(Object.keys(manifest).sort(),['hook','kind','notes','pool','token']);
assert.equal(manifest.kind,'univ4_hook');assert.equal(manifest.token.contract,'EHS');assert.equal(manifest.hook.contract,'EHSHook');
assert.equal(manifest.pool.fee,12500);assert.equal(manifest.pool.tickSpacing,60);
const payloadBytes=files.reduce((sum,file)=>sum+file.bytes,0);
const gitOverheadAllowance=(files.length+1)*1024;
const budgetBytes=8388608;
let reportBytes=0, report;
for(let i=0;i<5;i++){
  report=JSON.stringify({payloadBytes,reportBytes,gitOverheadAllowance,conservativeTotalBytes:payloadBytes+reportBytes+gitOverheadAllowance,budgetBytes,files},null,2)+'\n';
  if(Buffer.byteLength(report)===reportBytes)break;
  reportBytes=Buffer.byteLength(report);
}
assert.ok(payloadBytes+reportBytes+gitOverheadAllowance<=budgetBytes,'Submission exceeds 8 MiB conservative budget');
await writeFile(reportPath,report);
console.log(JSON.stringify({files:files.length+1,payloadBytes:payloadBytes+reportBytes,gitOverheadAllowance,conservativeTotalBytes:payloadBytes+reportBytes+gitOverheadAllowance,budgetBytes},null,2));

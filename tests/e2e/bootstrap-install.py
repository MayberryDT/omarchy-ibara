#!/usr/bin/env python3
"""Process E2E: real shell/checksum/download; record authenticated sh handoff.
Run in a new scratch directory: python3 /checkout/tests/e2e/bootstrap-install.py /checkout
Never executes the installer or installs packages. Writes bootstrap-results.json.
"""
import hashlib,json,os,pathlib,re,shlex,shutil,stat,subprocess,sys,urllib.request
source=pathlib.Path(sys.argv[1]).resolve();out=pathlib.Path.cwd()
qml=re.search(r'readonly property string ibaraInstallCommand: (".*")', (source/'Service.qml').read_text()).group(1)
command=json.loads(qml)
readme=re.search(r'## Install.*?```bash\n(.*?)```',(source/'README.md').read_text(),re.S).group(1).strip()
assert shlex.split(command)==shlex.split(' '.join(x.strip() for x in readme.splitlines()))
url=re.search(r'https://github.com/MayberryDT/ibara/releases/download/[^ ]+/install',command).group()
expected=re.search(r'\b[0-9a-f]{64}\b',command).group()
valid=urllib.request.urlopen(url,timeout=30).read();assert hashlib.sha256(valid).hexdigest()==expected
(out/'reviewed-installer').write_bytes(valid)
rows=[]
for entry,cmd in [('plugin',command),('readme',readme)]:
 for case in ['valid','tampered','truncated','empty','html','download-error','missing-curl','checksum-error','missing-checksum','public-download']:
  root=out/(entry+'-'+case);root.mkdir();tools=root/'bin';tools.mkdir();tmp=root/'private temporary files';tmp.mkdir();log=root/'handoff.json'
  for name in ['mktemp','rm','sha256sum']:
   if name=='sha256sum' and case=='missing-checksum':continue
   (tools/name).symlink_to(shutil.which(name))
  shell=tools/'sh';shell.write_text('''#!/usr/bin/python3
import hashlib,json,os,pathlib,stat,sys
p=pathlib.Path(sys.argv[1]);pathlib.Path(os.environ['HANDOFF_LOG']).write_text(json.dumps({'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'mode':stat.S_IMODE(p.stat().st_mode)}))
''');shell.chmod(0o755)
  payload=valid
  if case=='tampered':payload=valid+b'\necho altered\n'
  if case=='truncated':payload=valid[:128]
  if case=='empty':payload=b''
  if case=='html':payload=b'<html>upstream error</html>'
  fixture=root/'download';fixture.write_bytes(payload)
  curl=tools/'curl'
  if case=='public-download':curl.symlink_to(shutil.which('curl'))
  elif case!='missing-curl':
   curl.write_text('''#!/usr/bin/python3
import os,pathlib,sys
p=sys.argv[sys.argv.index('-o')+1];pathlib.Path(p).write_bytes(pathlib.Path(os.environ['DOWNLOAD_FIXTURE']).read_bytes());sys.exit(22 if os.environ['CASE']=='download-error' else 0)
''');curl.chmod(0o755)
  if case=='checksum-error':
   (tools/'sha256sum').unlink();(tools/'sha256sum').write_text('#!/usr/bin/python3\nraise SystemExit(2)\n');(tools/'sha256sum').chmod(0o755)
  env=dict(os.environ,PATH=str(tools),TMPDIR=str(tmp),HANDOFF_LOG=str(log),DOWNLOAD_FIXTURE=str(fixture),CASE=case)
  r=subprocess.run(['/bin/sh','-c',cmd],env=env,text=True,capture_output=True,timeout=210)
  success=case in ['valid','public-download'];assert (r.returncode==0)==success,(entry,case,r.stdout,r.stderr)
  assert log.exists()==success,(entry,case,'unexpected interpreter invocation')
  assert not list(tmp.iterdir()),(entry,case,'temporary file remains')
  if success:
   receipt=json.loads(log.read_text());assert receipt=={'sha256':expected,'mode':0o600},receipt
  rows.append({'entry':entry,'case':case,'exit_code':r.returncode,'interpreter_invoked':log.exists(),'temporary_files_cleaned':True,'passed':True})
result={'installer_url':url,'installer_sha256':expected,'readme_matches_plugin':True,'cases':rows}
(out/'bootstrap-results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))

import pathlib,os,subprocess,json,shutil,tempfile
p=pathlib.Path.cwd();tools=p/'button-bin';tools.mkdir();runtime_owner=tempfile.TemporaryDirectory(prefix='ibara-bootstrap-');runtime=pathlib.Path(runtime_owner.name);home=p/'button-home';home.mkdir();state=p/'button-state';state.mkdir()
for name in ['curl','sha256sum','mktemp','rm']:(tools/name).symlink_to(shutil.which(name))
for name in ['Commons','Ui']:(p/name).symlink_to('/usr/share/omarchy/shell/'+name)
(runtime/os.environ['WAYLAND_DISPLAY']).symlink_to(pathlib.Path(os.environ['XDG_RUNTIME_DIR'])/os.environ['WAYLAND_DISPLAY'])
shutil.copyfile(p/'terminal-launcher',tools/'omarchy-launch-floating-terminal-with-presentation');(tools/'omarchy-launch-floating-terminal-with-presentation').chmod(0o755)
shell=tools/'sh';shell.write_text('''#!/usr/bin/python3
import hashlib,json,os,pathlib,stat,sys
if sys.argv[1]=='-c':os.execv('/bin/sh',['sh']+sys.argv[1:])
p=pathlib.Path(sys.argv[1]);pathlib.Path(os.environ['HANDOFF_LOG']).write_text(json.dumps({'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'mode':stat.S_IMODE(p.stat().st_mode)}))
''');shell.chmod(0o755)
ibara=tools/'ibara';ibara.write_text('#!/usr/bin/python3\nimport os,pathlib,sys\npathlib.Path(os.environ["SETUP_LOG"]).write_text(" ".join(sys.argv[1:]))\n');ibara.chmod(0o755)
env=dict(os.environ,PATH=str(tools),HOME=str(home),XDG_STATE_HOME=str(state),XDG_RUNTIME_DIR=str(runtime),QT_QPA_PLATFORM='wayland',BUTTON_LOG=str(p/'button-launches.jsonl'),HANDOFF_LOG=str(p/'button-handoff.json'),SETUP_LOG=str(p/'button-setup.txt'),TMPDIR=str(p/'button-temp'))
(p/'button-temp').mkdir()
with (p/'button.log').open('w') as log:r=subprocess.run(['/usr/bin/quickshell','-p',str(p/'button.qml')],env=env,stdout=log,stderr=log,timeout=20)
assert r.returncode==0
launches=[json.loads(x) for x in (p/'button-launches.jsonl').read_text().splitlines()];assert len(launches)==2 and all(x['exit_code']==0 for x in launches),launches
import re
expected=json.loads(re.search(r'readonly property string ibaraInstallCommand: (".*")',(p/'plugin/Service.qml').read_text()).group(1))
assert launches[0]['command']==expected and launches[1]['command']=='ibara setup'
assert json.loads((p/'button-handoff.json').read_text())=={'sha256':'92591da2459f18da47b6567d47cb66c0b16b988d4752fa88ec67283021a03fbe','mode':0o600}
assert (p/'button-setup.txt').read_text()=='setup';assert not list((p/'button-temp').iterdir())
(p/'button-results.json').write_text(json.dumps({'real_qml_service':True,'install_command_matches_reviewed_source':True,'pinned_public_download_authenticated':True,'setup_branch_unchanged':True,'temporary_files_cleaned':True,'passed':True},indent=2)+'\n');print((p/'button-results.json').read_text())

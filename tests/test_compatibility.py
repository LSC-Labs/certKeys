import os, pathlib, re, shutil, subprocess, sys, tempfile
script=str(pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[1] / 'src' / 'certKeys')
with tempfile.TemporaryDirectory(prefix='certKeys test ') as root:
    home=pathlib.Path(root)/'home with spaces';home.mkdir()
    env=dict(os.environ,HOME=str(home))
    # Exercise the real version command without depending on GitHub or the network.
    version=re.search(r'^Prog_Version=(.+)$',pathlib.Path(script).read_text(),re.M).group(1)
    mock_bin=pathlib.Path(root)/'version bin';mock_bin.mkdir()
    curl=mock_bin/'curl'
    curl.write_text('#!/bin/bash\nif [ "$MOCK_CURL_FAIL" = 1 ]; then exit 22; fi\nprintf "%s\\n" "$MOCK_RELEASE"\n')
    curl.chmod(0o755)
    version_env=dict(env,PATH=str(mock_bin)+os.pathsep+env['PATH'])
    for tag, expected in [
        ('v'+version,'No newer release available.'),
        (version,'No newer release available.'),
        ('v0.0.0.0','No newer release available.'),
        ('v0.1.10.0','Update available:'),
        ('v1.0.0.0','Update available:'),
    ]:
        version_env['MOCK_RELEASE']='{"tag_name": "'+tag+'"}'
        result=subprocess.run(['/bin/bash',script,'createKeys','-VERSION'],env=version_env,cwd=root,text=True,capture_output=True)
        assert result.returncode==0,(result.stdout,result.stderr)
        assert 'certKeys version: '+version in result.stdout and expected in result.stdout
        if expected=='Update available:':
            assert '/releases/download/'+tag+'/certKeys' in result.stdout
        assert not (home/'.ssh').exists(), 'Version flag must not execute another command'
    for response, fail in [('{}','0'),('{"tag_name":"v1.2.3-rc1"}','0'),('not JSON','0'),('', '1')]:
        version_env.update(MOCK_RELEASE=response,MOCK_CURL_FAIL=fail)
        result=subprocess.run(['/bin/bash',script,'-version'],env=version_env,cwd=root,text=True,capture_output=True)
        assert result.returncode==1 and 'Update check failed:' in result.stderr
        assert 'certKeys version: '+version in result.stdout
        assert 'No newer release available.' not in result.stdout
    # Keep only the utilities needed to load the source script; curl is absent.
    missing_bin=pathlib.Path(root)/'without curl';missing_bin.mkdir()
    for utility in ('dirname','tr'):
        missing_bin.joinpath(utility).symlink_to(shutil.which(utility))
    result=subprocess.run(['/bin/bash',script,'-version'],env=dict(env,PATH=str(missing_bin)),cwd=root,text=True,capture_output=True)
    assert result.returncode==1 and 'curl is required' in result.stderr
    assert 'certKeys version: '+version in result.stdout
    def run(*args):
        p=subprocess.run(['/bin/bash',script,*args],env=env,cwd=root,input='n\n',text=True,capture_output=True)
        assert p.returncode==0,(args,p.stdout,p.stderr)
        assert not p.stderr or args[0] == "createKeys",(args,p.stderr)
        return p.stdout
    run('help','-TRACE')
    assert 'No private keys found.' in run('list')
    assert not (home/'.ssh').exists(), 'Listing must not create the SSH directory'
    ssh_dir=home/'.ssh';ssh_dir.mkdir(mode=0o700)
    assert 'No private keys found.' in run('list')
    fixtures={
        'custom key': '-----BEGIN OPENSSH PRIVATE KEY-----\nSECRET-LIST-TEST\n',
        '.hidden-key': '-----BEGIN ENCRYPTED PRIVATE KEY-----\r\nSECRET-LIST-TEST\r\n',
        'legacy-rsa': '-----BEGIN RSA PRIVATE KEY-----',
        'ec-key': '-----BEGIN EC PRIVATE KEY-----\nSECRET-LIST-TEST\n',
        'dsa-key': '-----BEGIN DSA PRIVATE KEY-----\nSECRET-LIST-TEST\n',
        'pkcs8': '-----BEGIN PRIVATE KEY-----\nSECRET-LIST-TEST\n',
        'id_fake.pub': 'ssh-rsa AAAA public key\n',
        'config': 'Host example\n HostName example.com\n',
    }
    for name, content in fixtures.items():
        (ssh_dir/name).write_bytes(content.encode())
        (ssh_dir/name).chmod(0o600)
    (ssh_dir/'subdirectory').mkdir()
    (ssh_dir/'subdirectory/nested-key').write_text(fixtures['pkcs8'])
    listing=run('LiSt','-context','ignored','-default')
    for name in ('custom key','.hidden-key','legacy-rsa','ec-key','dsa-key','pkcs8'):
        assert str(ssh_dir/name) in listing,(name,listing)
    assert 'SECRET-LIST-TEST' not in listing
    assert str(ssh_dir/'id_fake.pub') not in listing and str(ssh_dir/'config') not in listing
    assert 'nested-key' not in listing
    permission_key=ssh_dir/'custom key'
    for mode, warning in [(0o400,False),(0o600,False),(0o644,True),(0o640,True),(0o700,True)]:
        permission_key.chmod(mode)
        checked=subprocess.run(['/bin/bash',script,'list'],env=env,cwd=root,text=True,capture_output=True)
        assert checked.returncode==0 and str(permission_key) in checked.stdout
        assert ('[W]' in checked.stderr)==warning,(mode,checked.stderr)
        if warning: assert str(permission_key) in checked.stderr and 'chmod 600' in checked.stderr
        assert permission_key.stat().st_mode & 0o777 == mode, 'List must not change permissions'
        assert 'SECRET-LIST-TEST' not in checked.stdout+checked.stderr
    permission_key.chmod(0o600)
    # Force metadata failures and a foreign owner without privileged chown operations.
    stat_bin=pathlib.Path(root)/'stat bin';stat_bin.mkdir()
    stat=stat_bin/'stat'
    stat_env=dict(env,PATH=str(stat_bin)+os.pathsep+env['PATH'])
    for body, expected in [('exit 1','Cannot check private key permissions'),
                           ("printf '%s\\n' '"+str(os.getuid()+1)+" 600'",'owner UID')]:
        stat.write_text('#!/bin/sh\n'+body+'\n');stat.chmod(0o755)
        checked=subprocess.run(['/bin/bash',script,'list'],env=stat_env,cwd=root,text=True,capture_output=True)
        assert checked.returncode==0 and expected in checked.stderr,(checked.stdout,checked.stderr)
    if sys.platform=='darwin':
        subprocess.run(['chmod','+a','everyone allow read',str(permission_key)],check=True)
        try:
            checked=subprocess.run(['/bin/bash',script,'list'],env=env,cwd=root,text=True,capture_output=True)
            assert checked.returncode==0 and 'additional ACL grants' in checked.stderr
        finally:
            subprocess.run(['chmod','-N',str(permission_key)],check=True)
    for name in fixtures: (ssh_dir/name).unlink()
    shutil.rmtree(ssh_dir/'subdirectory')
    run('createKeys','-DEFAULT','-keybits','1024')
    key=home/'.ssh/id_rsa'
    assert key.exists() and key.stat().st_mode & 0o777 == 0o600
    p=subprocess.run(['openssl','pkey','-in',str(key),'-text','-noout'],capture_output=True,text=True)
    assert '1024 bit' in p.stdout
    run('createPublicKeys','-default')
    # A named context must select the same key for all subsequent operations.
    run('createKeys','-context','linux-test','-keybits','2048')
    context_key=home/'.ssh/id@linux-test_rsa'
    assert context_key.exists()
    listing=run('list')
    assert str(key) in listing and str(context_key) in listing
    assert str(key)+'.pub' not in listing and str(context_key)+'.pub' not in listing
    run('createPublicKeys','-context','linux-test')
    run('makeKeyAsDefault','-context','linux-test')
    assert key.read_bytes()==context_key.read_bytes()
    assert (home/'.ssh/id_rsa.pub').read_bytes()==(home/'.ssh/id@linux-test_rsa.pub').read_bytes()
    out=pathlib.Path(root)/'export';out.mkdir()
    run('getPublicSSHKey','-default','-target',str(out))
    assert (out/'id_rsa.pub').exists()
    run('createConfigEntry','-target','alice@first.example','-alias','first')
    run('createConfigEntry','-target','bob@second.example','-alias','second')
    run('createConfigEntry','-target','carol@first.example','-alias','first')
    config=home/'.ssh/config'
    assert config.read_text().count('Host first\n')==1
    assert 'User          carol' in config.read_text()
    run('createConfigEntry','-target','host-only.example','-alias','host-only','-context','linux-test')
    host_block=config.read_text().split('Host host-only\n',1)[1]
    assert 'HostName      host-only.example' in host_block
    assert 'IdentityFile  ~/.ssh/id@linux-test_rsa' in host_block
    assert 'User ' not in host_block
    # Ask OpenSSH to parse the generated config without making a connection.
    parsed=subprocess.run(['ssh','-G','-F',str(config),'host-only'],text=True,capture_output=True)
    assert parsed.returncode==0,parsed.stderr
    assert 'hostname host-only.example\n' in parsed.stdout
    assert 'identityfile ~/.ssh/id@linux-test_rsa\n' in parsed.stdout
    assert config.read_text() in run('showConfig')
    run('removeConfigEntry','-alias','first')
    assert 'Host first\n' not in config.read_text() and 'Host second\n' in config.read_text()
    # Mock only OS detection; sync still runs against real temporary files.
    bin_dir=pathlib.Path(root)/'bin';bin_dir.mkdir()
    uname=bin_dir/'uname'
    uname.write_text('#!/bin/sh\ncase "$1" in\n-s) echo "$TEST_SYSTEM" ;;\n-r) echo "$TEST_RELEASE" ;;\nesac\n')
    uname.chmod(0o755)
    env['PATH']=str(bin_dir)+os.pathsep+env['PATH']
    env.pop('WSL_INTEROP',None)
    env.pop('WSL_DISTRO_NAME',None)
    for system, release, available in [
        ('Darwin','25.0',False), ('Linux','6.8.0-generic',False),
        ('Linux','6.6.0-microsoft-standard-WSL2',True),
        ('MINGW64_NT-10.0','3.0',True), ('MSYS_NT-10.0','3.0',True),
        ('CYGWIN_NT-10.0','3.0',True),
    ]:
        env.update(TEST_SYSTEM=system,TEST_RELEASE=release)
        help_text=run('help')
        assert ('syncKeysToWindows' in help_text)==available
        assert ('syncKeysFromWindows' in help_text)==available
        if not available:
            for command in ('syncKeysToWindows','syncKeysFromWindows'):
                result=subprocess.run(['/bin/bash',script,command],env=env,cwd=root,text=True,capture_output=True)
                assert result.returncode!=0 and 'require a Unix shell' in result.stderr
            assert not (pathlib.Path(root)/'.ssh').exists()
    env.update(TEST_SYSTEM='Linux',TEST_RELEASE='6.6.0-microsoft-standard-WSL2')
    windows=pathlib.Path(root)/'.ssh';windows.mkdir()
    run('syncKeysToWindows')
    assert (windows/'id_rsa').exists()
    before=(windows/'config').read_bytes()
    run('syncKeysFromWindows')
    assert (windows/'config').read_bytes()==before
    assert config.read_text().count('Host second\n')==1
    print('PASS: keys, contexts, defaults, export, OpenSSH config validation, sync, and OS availability checks.')

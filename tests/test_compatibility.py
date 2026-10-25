import os, pathlib, subprocess, sys, tempfile
script=str(pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[1] / 'src' / 'certKeys')
with tempfile.TemporaryDirectory(prefix='certKeys test ') as root:
    home=pathlib.Path(root)/'home with spaces';home.mkdir()
    env=dict(os.environ,HOME=str(home))
    def run(*args):
        p=subprocess.run(['/bin/bash',script,*args],env=env,cwd=root,input='n\n',text=True,capture_output=True)
        assert p.returncode==0,(args,p.stdout,p.stderr)
        assert not p.stderr or args[0] == "createKeys",(args,p.stderr)
        return p.stdout
    run('help','-TRACE')
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

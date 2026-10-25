param([string]$ScriptPath = (Join-Path $PSScriptRoot '../src/certKeys.ps1'))
$ErrorActionPreference = 'Stop'
$ScriptPath = (Resolve-Path -LiteralPath $ScriptPath).Path
function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$parseErrors)
Assert ($parseErrors.Count -eq 0) 'PowerShell parse failed'
# Load the actual functions without running the CLI or touching the real user profile.
foreach ($node in $ast.EndBlock.Statements) {
    if ($node -is [Management.Automation.Language.FunctionDefinitionAst]) {
        . ([scriptblock]::Create($node.Extent.Text))
    }
}
$Prog_Version = [regex]::Match([IO.File]::ReadAllText($ScriptPath), "\`$Prog_Version = '([^']+)'").Groups[1].Value
$root = Join-Path ([IO.Path]::GetTempPath()) ('certKeys Windows test ' + [guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($root)
try {
    if ($env:OS -ne 'Windows_NT') {
        # On Unix, verify the common PowerShell logic and real crypto commands;
        # the Windows CI matrix executes the actual Windows ACL implementation.
        function Set-KeyAccess([string]$Path, [bool]$Directory = $false) {
            $mode = '600'; if ($Directory) { $mode = '700' }
            & chmod $mode $Path
            Assert ($LASTEXITCODE -eq 0) 'chmod failed'
        }
        function Test-PrivateKeyAccess([string]$Path) { }
    }
    function Read-Confirmation { return $false }
    $KeyLocation = Join-Path $root 'home with spaces/.ssh'
    $ConfigFile = Join-Path $KeyLocation 'config'
    $Algorithm = 'rsa'; $KeyBits = '1024'
    $KeyName = 'id@windows-test_rsa'
    $PrivateKey = Join-Path $KeyLocation $KeyName
    $DefaultKey = Join-Path $KeyLocation 'id_rsa'
    $Options = @{ force = '1' }
    Assert (((Show-PrivateKeys) -join "`n") -match 'No private keys found.') 'Missing SSH directory should be empty'
    Assert (-not (Test-Path -LiteralPath $KeyLocation)) 'Listing created SSH directory'
    Initialize-KeyDirectory
    Assert (((Show-PrivateKeys) -join "`n") -match 'No private keys found.') 'Empty SSH directory should be empty'
    New-KeyPair
    Assert (Test-Path -LiteralPath $PrivateKey) 'Private key missing'
    foreach ($suffix in @('.pub','.pub.pem')) {
        Assert (Test-Path -LiteralPath ($PrivateKey + $suffix)) "Public key missing: $suffix"
        $bytes = [IO.File]::ReadAllBytes($PrivateKey + $suffix)
        Assert ($bytes[0] -ne 0xef -and $bytes[0] -ne 0xff) 'Public key has a BOM'
    }
    $keyInfo = (Invoke-Native 'openssl' @('pkey','-in',$PrivateKey,'-text','-noout')) -join "`n"
    Assert ($keyInfo -match '1024 bit') 'Wrong key size'
    New-PublicKeys
    Copy-DefaultKeys
    Assert ([IO.File]::ReadAllText($DefaultKey) -eq [IO.File]::ReadAllText($PrivateKey)) 'Default key differs'
    $listFixtures = @{
        'custom key' = "-----BEGIN OPENSSH PRIVATE KEY-----`nSECRET-LIST-TEST`n"
        '.hidden-key' = "-----BEGIN ENCRYPTED PRIVATE KEY-----`r`nSECRET-LIST-TEST`r`n"
        'legacy-rsa' = '-----BEGIN RSA PRIVATE KEY-----'
        'ec-key' = "-----BEGIN EC PRIVATE KEY-----`nSECRET-LIST-TEST`n"
        'dsa-key' = "-----BEGIN DSA PRIVATE KEY-----`nSECRET-LIST-TEST`n"
        'pkcs8' = "-----BEGIN PRIVATE KEY-----`nSECRET-LIST-TEST`n"
        'config' = "Host example`n HostName example.com`n"
    }
    foreach ($name in $listFixtures.Keys) { Write-Utf8File (Join-Path $KeyLocation $name) $listFixtures[$name] }
    $nested = Join-Path $KeyLocation 'subdirectory'; [void][IO.Directory]::CreateDirectory($nested)
    Write-Utf8File (Join-Path $nested 'nested-key') $listFixtures['pkcs8']
    $listing = @(Show-PrivateKeys)
    foreach ($name in @('custom key','.hidden-key','legacy-rsa','ec-key','dsa-key','pkcs8')) {
        Assert ($listing -contains (Join-Path $KeyLocation $name)) "Listing omitted $name"
    }
    Assert ($listing -contains $PrivateKey -and $listing -contains $DefaultKey) 'Real keys missing from list'
    Assert ($listing -notcontains "$PrivateKey.pub" -and $listing -notcontains "$PrivateKey.pub.pem") 'Public keys listed'
    Assert (($listing -join "`n") -notmatch 'SECRET-LIST-TEST|nested-key') 'Listing exposes content or recurses'
    Assert ($listing -notcontains $ConfigFile) 'SSH config listed as a private key'
    foreach ($name in $listFixtures.Keys) { Remove-Item -LiteralPath (Join-Path $KeyLocation $name) -Force }
    Remove-Item -LiteralPath $nested -Recurse -Force
    if ($env:OS -eq 'Windows_NT') {
        $acl = Get-Acl -LiteralPath $PrivateKey
        Assert $acl.AreAccessRulesProtected 'Private key inherits permissions'
        $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $rules = @($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
        Assert ($rules.Count -eq 1 -and $rules[0].IdentityReference.Value -eq $currentSid) 'Private key allows another identity'
        function Get-PermissionWarning([string]$Path) {
            $originalError = [Console]::Error
            $warnings = New-Object IO.StringWriter
            try {
                [Console]::SetError($warnings)
                Test-PrivateKeyAccess $Path
                return $warnings.ToString()
            } finally { [Console]::SetError($originalError); $warnings.Dispose() }
        }
        Assert ([string]::IsNullOrEmpty((Get-PermissionWarning $PrivateKey))) 'Secure ACL generated a warning'
        $everyone = New-Object Security.Principal.SecurityIdentifier('S-1-1-0')
        $grant = New-Object Security.AccessControl.FileSystemAccessRule($everyone, 'Read', 'Allow')
        $acl.AddAccessRule($grant)
        Set-Acl -LiteralPath $PrivateKey -AclObject $acl
        $warning = Get-PermissionWarning $PrivateKey
        Assert ($warning.Contains($PrivateKey) -and $warning.Contains('S-1-1-0')) 'Broad ACL did not warn'
        $after = Get-Acl -LiteralPath $PrivateKey
        Assert (@($after.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]) | Where-Object { $_.IdentityReference.Value -eq 'S-1-1-0' }).Count -eq 1) 'Permission check modified ACL'
        Set-KeyAccess $PrivateKey
        $acl = Get-Acl -LiteralPath $PrivateKey
        $acl.SetAccessRuleProtection($false, $true)
        Set-Acl -LiteralPath $PrivateKey -AclObject $acl
        Assert ((Get-PermissionWarning $PrivateKey) -match 'inheritance is enabled') 'Inheritance did not warn'
        Set-KeyAccess $PrivateKey
        Assert ([string]::IsNullOrEmpty((Get-PermissionWarning $PrivateKey))) 'Repaired ACL still warned'
        Assert ((Get-PermissionWarning (Join-Path $root 'missing-key')) -match 'Cannot check') 'ACL inspection failure was silent'
    }
    $Options = @{ target = 'alice@first.example'; alias = 'first' }; Add-ConfigEntry
    $Options = @{ target = 'bob@second.example'; alias = 'second' }; Add-ConfigEntry
    $Options = @{ target = 'carol@first.example'; alias = 'first' }; Add-ConfigEntry
    $config = [IO.File]::ReadAllText($ConfigFile)
    Assert (([regex]::Matches($config,'(?m)^Host first$')).Count -eq 1) 'Duplicate Host'
    Assert ($config -match 'User          carol') 'User not replaced'
    $Options = @{ target = 'host-only.example'; alias = 'host-only' }; Add-ConfigEntry
    $config = [IO.File]::ReadAllText($ConfigFile)
    Assert (($config -split 'Host host-only')[1] -notmatch 'User ') 'Host-only entry has a user'
    $parsed = (Invoke-Native 'ssh' @('-G','-F',$ConfigFile,'host-only')) -join "`n"
    Assert ($parsed -match 'hostname host-only.example') 'OpenSSH rejects generated config'
    $Options = @{ alias = 'first' }; Remove-ConfigEntry
    $config = [IO.File]::ReadAllText($ConfigFile)
    Assert ($config -notmatch 'Host first\n' -and $config -match 'Host second\n') 'Wrong entry removed'
    $otherHome = Join-Path $root 'other home'
    $otherSsh = Join-Path $otherHome '.ssh'; [void][IO.Directory]::CreateDirectory($otherSsh)
    Write-Utf8File (Join-Path $otherSsh 'config') "Host existing`n HostName existing.example`n"
    $Options = @{ target = $otherHome }
    Sync-Keys $false
    Assert (Test-Path -LiteralPath (Join-Path $otherSsh $KeyName)) 'Windows key export missing'
    Sync-Keys $true
    $config = [IO.File]::ReadAllText($ConfigFile)
    Assert ($config -match 'Host existing' -and ([regex]::Matches($config,'(?m)^Host second$')).Count -eq 1) 'Config sync failed'
    $Options = @{ target = (Split-Path $KeyLocation) }
    $rejected = $false
    try { Sync-Keys $true } catch { $rejected = $true }
    Assert $rejected 'Sync to same directory should fail'
    $merged = Remove-HostBlock "# header`nHost a b`n HostName old`nMatch all`n X yes`nHost keep`n HostName keep`n" 'b'
    Assert ($merged -notmatch 'Host a b' -and $merged -match 'Match all' -and $merged -match 'Host keep') 'Block boundaries broken'
    # Mock only network I/O; compare actual PowerShell version output.
    function Invoke-RestMethod { return @{ tag_name = $script:TestTag } }
    foreach ($tag in @(('v' + $Prog_Version),$Prog_Version,'v0.0.1.0','v0.1.10.0','v1.0.0.0')) {
        $script:TestTag = $tag
        $out = (Show-Version) -join "`n"
        $isNewer = [version]($tag -replace '^v','') -gt [version]$Prog_Version
        Assert (($out -match 'Update available:') -eq $isNewer) 'Version comparison failed'
        if ($isNewer) { Assert ($out -match '/certKeys.ps1') 'Wrong Windows download' }
    }
    $script:TestTag = 'invalid'
    $rejected = $false
    try { Show-Version | Out-Null } catch { $rejected = $true }
    Assert $rejected 'Malformed release accepted'
    function Invoke-RestMethod { throw 'Offline' }
    $rejected = $false
    try { Show-Version | Out-Null } catch { $rejected = $true }
    Assert $rejected 'Network error not reported'
    # Test remote installation without contacting a server: inspect stdin and command.
    function Invoke-Native($Program, $Arguments, $InputText) {
        Assert ($Program -eq 'ssh') 'Expected SSH'
        Assert ($InputText -match "key='ssh-rsa " -and $InputText -notmatch 'PRIVATE KEY') 'SSH stdin must contain only public key material'
        Assert ($Arguments[1] -eq 'sh -s' -and $InputText -match 'grep -qxF') 'Remote installation must avoid duplicates'
        if ($env:OS -ne 'Windows_NT') {
            $oldHome = $env:HOME
            try {
                $env:HOME = Join-Path $root 'remote home'
                [void][IO.Directory]::CreateDirectory($env:HOME)
                $InputText | & /bin/sh
                Assert ($LASTEXITCODE -eq 0) 'Remote installation script failed'
                $InputText | & /bin/sh
                Assert ($LASTEXITCODE -eq 0) 'Repeated remote installation failed'
                $authorized = [IO.File]::ReadAllText((Join-Path $env:HOME '.ssh/authorized_keys'))
                Assert (([regex]::Matches($authorized,'(?m)^ssh-rsa ')).Count -eq 1) 'Duplicate remote key'
            } finally { $env:HOME = $oldHome }
        }
        $script:Sent = $true
    }
    $Options = @{ target = 'alice@server.example' }; $script:Sent = $false
    Send-PublicKey
    Assert $script:Sent 'SSH key transfer not invoked'
    $help = (& $ScriptPath help) -join "`n"
    Assert ($help -match 'syncKeysToWindows' -and $help -match 'createKeys') 'CLI help missing'
    if ($env:OS -eq 'Windows_NT') {
        # Exercise the complete Windows entry point against an isolated profile.
        $cliHome = Join-Path $root 'cli home'
        $isolatedScript = Join-Path $root 'certKeys.ps1'
        $text = [IO.File]::ReadAllText($ScriptPath).Replace(
            "([Environment]::GetFolderPath('UserProfile'))", "'" + $cliHome.Replace("'", "''") + "'")
        Write-Utf8File $isolatedScript $text
        $engine = (Get-Process -Id $PID).Path
        & $engine -NoProfile -ExecutionPolicy Bypass -File $isolatedScript createKeys -DEFAULT -force -keybits 1024
        Assert ($LASTEXITCODE -eq 0) 'CLI key creation failed'
        $cliKey = Join-Path $cliHome '.ssh/id_rsa'
        Assert (Test-Path -LiteralPath $cliKey) 'CLI ignored -default'
        $cliListing = (& $engine -NoProfile -ExecutionPolicy Bypass -File $isolatedScript LiSt) -join "`n"
        Assert ($LASTEXITCODE -eq 0 -and $cliListing.Contains($cliKey)) 'CLI list failed'
        Assert (-not $cliListing.Contains($cliKey + '.pub')) 'CLI listed public keys'
        $export = Join-Path $root 'export.pub'
        & $engine -NoProfile -ExecutionPolicy Bypass -File $isolatedScript getPublicSSHKey -default -target $export
        Assert ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $export)) 'CLI export failed'
        & $engine -NoProfile -ExecutionPolicy Bypass -File $isolatedScript createConfigEntry -default -target 'alice@cli.example' -alias 'cli'
        Assert ($LASTEXITCODE -eq 0) 'CLI config creation failed'
        & $engine -NoProfile -ExecutionPolicy Bypass -File $isolatedScript removeConfigEntry -alias 'cli'
        Assert ($LASTEXITCODE -eq 0) 'CLI config removal failed'
        Assert ([IO.File]::ReadAllText((Join-Path $cliHome '.ssh/config')) -notmatch 'Host cli') 'CLI did not remove entry'
    }
    Write-Output 'PASS: PowerShell parsing, real keys, defaults, config, sync, update checks and SSH transfer.'
    } finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

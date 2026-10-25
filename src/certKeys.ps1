#requires -Version 5.1
# Native Windows edition. Requires Windows OpenSSH Client and OpenSSL on PATH.
# (c) 2024-2026 LSC Labs
$Prog_Version = '0.1.2.0'
$ErrorActionPreference = 'Stop'

function Test-TrueValue($Value) {
    return ([string]$Value).ToLowerInvariant() -notin @('', '0', 'false', 'no', 'n', '-')
}

function Read-Confirmation([string]$Message, [bool]$DefaultYes = $false) {
    $answer = Read-Host $Message
    if ([string]::IsNullOrEmpty($answer)) { return $DefaultYes }
    return $answer -match '^[yY]$'
}

function Write-TraceMessage([string]$Message) {
    if (Test-TrueValue $Options['trace']) { [Console]::Error.WriteLine("[T] $Message") }
}

function Invoke-Native([string]$Program, [string[]]$Arguments, [string]$InputText) {
    if (-not (Get-Command $Program -CommandType Application -ErrorAction SilentlyContinue)) {
        throw "Required program not found on PATH: $Program"
    }
    Write-TraceMessage ($Program + ' ' + ($Arguments -join ' '))
    if ($PSBoundParameters.ContainsKey('InputText')) { $InputText | & $Program @Arguments }
    else { & $Program @Arguments }
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}

function Write-Utf8File([string]$Path, [string]$Text) {
    # Windows PowerShell 5.1 otherwise writes UTF-16 for redirection.
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Set-KeyAccess([string]$Path, [bool]$Directory = $false) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    if ($Directory) {
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    } else {
        $acl = New-Object Security.AccessControl.FileSecurity
        $inherit = [Security.AccessControl.InheritanceFlags]::None
    }
    $acl.SetOwner($identity)
    $acl.SetAccessRuleProtection($true, $false)
    $rule = New-Object Security.AccessControl.FileSystemAccessRule(
        $identity, 'FullControl', $inherit, 'None', 'Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Initialize-KeyDirectory {
    if (-not (Test-Path -LiteralPath $KeyLocation -PathType Container)) {
        [void][IO.Directory]::CreateDirectory($KeyLocation)
        Set-KeyAccess $KeyLocation $true
    }
}

function New-PublicKeys {
    if (-not (Test-Path -LiteralPath $PrivateKey -PathType Leaf)) {
        if (-not (Read-Confirmation 'Private key missing. Create it now? [N/y]')) {
            throw "Private key missing: $PrivateKey"
        }
        New-KeyPair
        return
    }
    Invoke-Native 'openssl' @('pkey', '-in', $PrivateKey, '-pubout', '-out', "$PrivateKey.pub.pem")
    $public = @(Invoke-Native 'ssh-keygen' @('-y', '-f', $PrivateKey)) -join "`n"
    Write-Utf8File "$PrivateKey.pub" ($public.Trim() + "`n")
}

function New-KeyPair {
    Initialize-KeyDirectory
    if ((Test-Path -LiteralPath $PrivateKey) -and -not (Test-TrueValue $Options['force'])) {
        if (-not (Read-Confirmation "Overwrite existing key $PrivateKey ? [Y/n]" $true)) { return }
    }
    # Restrict access before OpenSSL writes the private key, including when overwriting.
    if (-not (Test-Path -LiteralPath $PrivateKey)) { Write-Utf8File $PrivateKey '' }
    Set-KeyAccess $PrivateKey
    Invoke-Native 'openssl' @('genpkey', '-algorithm', $Algorithm.ToUpperInvariant(),
        '-pkeyopt', "rsa_keygen_bits:$KeyBits", '-out', $PrivateKey)
    New-PublicKeys
    Write-Output "Keys created: $PrivateKey"
    if ($PrivateKey -ne $DefaultKey -and -not (Test-Path -LiteralPath $DefaultKey)) {
        if (Read-Confirmation 'Make this key the default as well? [Y/n]' $true) { Copy-DefaultKeys }
    }
}

function Copy-DefaultKeys {
    foreach ($suffix in @('', '.pub', '.pub.pem')) {
        if (-not (Test-Path -LiteralPath ($PrivateKey + $suffix) -PathType Leaf)) {
            throw "Key file missing: $PrivateKey$suffix"
        }
    }
    if ($PrivateKey -eq $DefaultKey) { return }
    if (-not (Test-Path -LiteralPath $DefaultKey)) { Write-Utf8File $DefaultKey '' }
    Set-KeyAccess $DefaultKey
    foreach ($suffix in @('', '.pub', '.pub.pem')) {
        Copy-Item -LiteralPath ($PrivateKey + $suffix) -Destination ($DefaultKey + $suffix) -Force
    }
    Set-KeyAccess $DefaultKey
}

function Get-TargetParts {
    if (-not $Options['target']) { throw 'Specify -target user@host or -target host.' }
    $parts = ([string]$Options['target']) -split '@', 2
    $userName = ''
    $hostName = $parts[0]
    if ($parts.Count -eq 2) { $userName = $parts[0]; $hostName = $parts[1] }
    if ($hostName -notmatch '^[a-zA-Z0-9_.:\[\]-]+$' -or $hostName.StartsWith('-') -or
        ($userName -and ($userName -notmatch '^[a-zA-Z0-9_.-]+$' -or $userName.StartsWith('-')))) {
        throw 'Invalid SSH target. Use user@host or host without spaces or SSH options.'
    }
    return @{ User = $userName; HostName = $hostName }
}

function Get-EntryAlias {
    $entry = [string]$Options['alias']
    if (-not $entry) {
        $targetParts = Get-TargetParts
        $entry = $targetParts.HostName
        if ($entry -notmatch '^\d{1,3}(\.\d{1,3}){3}$' -and $entry -notmatch ':') {
            $entry = ($entry -split '\.')[0]
        }
    }
    if ($entry -notmatch '^[a-zA-Z0-9_.:\[\]-]+$' -or $entry.StartsWith('-')) {
        throw 'Use a simple SSH alias without whitespace, wildcards or path separators.'
    }
    return $entry
}

function Remove-HostBlock([string]$Text, [string]$EntryAlias) {
    $skip = $false
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^\s*(Host|Match)\s+(.+)$') {
            $skip = $Matches[1] -ieq 'Host' -and
                (($Matches[2] -split '\s+') -contains $EntryAlias)
        }
        if (-not $skip) { $lines.Add($line) }
    }
    return ($lines -join "`n").TrimEnd("`n")
}

function Set-ConfigText([string]$Text) {
    Initialize-KeyDirectory
    if (-not (Test-Path -LiteralPath $ConfigFile)) { Write-Utf8File $ConfigFile '' }
    Set-KeyAccess $ConfigFile
    Write-Utf8File $ConfigFile ($Text.TrimEnd("`r", "`n") + "`n")
}

function Add-ConfigEntry {
    $targetParts = Get-TargetParts
    $entry = Get-EntryAlias
    $text = ''
    if (Test-Path -LiteralPath $ConfigFile) { $text = [IO.File]::ReadAllText($ConfigFile) }
    $text = Remove-HostBlock $text $entry
    if ($text) { $text += "`n`n" }
    $text += "Host $entry`n     HostName      $($targetParts.HostName)`n     IdentityFile  ~/.ssh/$KeyName`n"
    if ($targetParts.User) { $text += "     User          $($targetParts.User)`n" }
    Set-ConfigText $text
}

function Remove-ConfigEntry {
    $entry = Get-EntryAlias
    if (Test-Path -LiteralPath $ConfigFile) {
        Set-ConfigText (Remove-HostBlock ([IO.File]::ReadAllText($ConfigFile)) $entry)
    }
}

function Send-PublicKey {
    $targetParts = Get-TargetParts
    if (-not (Test-Path -LiteralPath "$PrivateKey.pub")) {
        if (-not (Read-Confirmation 'Public key missing. Create keys now? [N/y]')) {
            throw "Public key missing: $PrivateKey.pub"
        }
        New-PublicKeys
    }
    # Windows has no ssh-copy-id. Send only the public key via SSH stdin.
    # The remote target uses a POSIX shell, as with the Bash edition's ssh-copy-id.
    $public = [IO.File]::ReadAllText("$PrivateKey.pub").Trim()
    if ($public -notmatch '^ssh-rsa [A-Za-z0-9+/=]+(?: [^\r\n]*)?$') {
        throw 'Invalid SSH public key.'
    }
    # Send a script through stdin to avoid Windows native-argument quote conversion.
    $escapedPublic = $public.Replace("'", "'\''")
    $remote = "key='$escapedPublic'`n" + 'umask 077; mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/authorized_keys" && chmod 700 "$HOME/.ssh" && chmod 600 "$HOME/.ssh/authorized_keys" && { grep -qxF -- "$key" "$HOME/.ssh/authorized_keys" || printf ''\n%s\n'' "$key" >> "$HOME/.ssh/authorized_keys"; }'
    $previousEncoding = $OutputEncoding
    try {
        $OutputEncoding = New-Object Text.UTF8Encoding($false)
        Invoke-Native 'ssh' @([string]$Options['target'], 'sh -s') ($remote + "`n")
    } finally { $OutputEncoding = $previousEncoding }
    if (Read-Confirmation 'Create a local SSH config entry too? [Y/n]' $true) { Add-ConfigEntry }
}

function Merge-Config([string]$SourceFile, [string]$DestinationFile) {
    if (-not (Test-Path -LiteralPath $SourceFile)) { return }
    $destinationText = ''
    if (Test-Path -LiteralPath $DestinationFile) { $destinationText = [IO.File]::ReadAllText($DestinationFile) }
    $sourceText = [IO.File]::ReadAllText($SourceFile)
    # Copy entire Host blocks, including multi-alias blocks; preserve unrelated destination blocks.
    $blocks = [regex]::Matches($sourceText, '(?ims)^\s*Host[ \t]+([^\r\n]+)\r?\n.*?(?=^[ \t]*(?:Host|Match)[ \t]+|\z)')
    foreach ($block in $blocks) {
        foreach ($entry in ($block.Groups[1].Value.Trim() -split '\s+')) {
            $destinationText = Remove-HostBlock $destinationText $entry
        }
        $destinationText = $destinationText.TrimEnd("`r", "`n") + "`n" + $block.Value.TrimEnd("`r", "`n") + "`n"
    }
    Write-Utf8File $DestinationFile $destinationText
}

function Sync-Keys([bool]$ToWindows) {
    # -target names the other home directory; default: current directory, as in Bash.
    $otherHome = [string]$Options['target']
    if (-not $otherHome) { $otherHome = (Get-Location).Path }
    $other = [IO.Path]::GetFullPath((Join-Path $otherHome '.ssh'))
    if ($other.TrimEnd('\', '/') -ieq $KeyLocation.TrimEnd('\', '/')) {
        throw 'Select a different home directory with -target or change the current directory.'
    }
    if (-not (Test-Path -LiteralPath $other -PathType Container)) {
        throw "Other .ssh directory missing: $other"
    }
    Initialize-KeyDirectory
    $sourceDir = $KeyLocation; $destinationDir = $other
    if ($ToWindows) { $sourceDir = $other; $destinationDir = $KeyLocation }
    foreach ($file in (Get-ChildItem -LiteralPath $sourceDir -File -Filter 'id*')) {
        $destination = Join-Path $destinationDir $file.Name
        if ($file.Name -notmatch '\.pub(?:\.pem)?$') {
            if (-not (Test-Path -LiteralPath $destination)) { Write-Utf8File $destination '' }
            Set-KeyAccess $destination
        }
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
        if ($file.Name -notmatch '\.pub(?:\.pem)?$') { Set-KeyAccess $destination }
    }
    $destinationConfig = Join-Path $destinationDir 'config'
    if (Test-Path -LiteralPath (Join-Path $sourceDir 'config')) {
        if (-not (Test-Path -LiteralPath $destinationConfig)) { Write-Utf8File $destinationConfig '' }
        Set-KeyAccess $destinationConfig
        Merge-Config (Join-Path $sourceDir 'config') $destinationConfig
    }
}

function Show-Version {
    Write-Output "certKeys version: $Prog_Version"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $release = Invoke-RestMethod -UseBasicParsing -Uri 'https://api.github.com/repos/LSC-Labs/certKeys/releases/latest' -TimeoutSec 10 -Headers @{ Accept = 'application/vnd.github+json' } -UserAgent 'certKeys'
        $tag = [string]$release.tag_name
        $latest = $tag -creplace '^v', ''
        if ($latest -notmatch '^\d+(\.\d+){1,3}$') { throw 'Unsupported release version.' }
        Write-Output "Latest GitHub release: $latest"
        if ([version]$latest -gt [version]$Prog_Version) {
            Write-Output "Update available: $Prog_Version -> $latest"
            Write-Output "Download: https://github.com/LSC-Labs/certKeys/releases/download/$tag/certKeys.ps1"
        } else { Write-Output 'No newer release available.' }
    } catch { throw "Update check failed: $($_.Exception.Message)" }
}

function Test-PrivateKeyAccess([string]$Path) {
    try {
        $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $acl = Get-Acl -LiteralPath $Path
        $ownerSid = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
        $reasons = New-Object 'System.Collections.Generic.List[string]'
        if ($ownerSid -ne $currentSid) { $reasons.Add('owner is not the current user') }
        if (-not $acl.AreAccessRulesProtected) { $reasons.Add('ACL inheritance is enabled') }
        $allowed = @($currentSid, 'S-1-5-18', 'S-1-5-32-544') # User, SYSTEM, Administrators.
        foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
                $rule.IdentityReference.Value -notin $allowed -and [int]$rule.FileSystemRights -ne 0) {
                $reasons.Add("ACL grants access to $($rule.IdentityReference.Value)")
            }
        }
        if ($reasons.Count) {
            [Console]::Error.WriteLine("[W] Private key permissions need attention: $Path ($($reasons -join '; ')). Review ownership and ACLs using Windows file security settings or icacls.")
        }
    } catch {
        [Console]::Error.WriteLine("[W] Cannot check private key permissions: $Path ($($_.Exception.Message))")
    }
}

function Show-PrivateKeys {
    Write-Output "Private keys in ${KeyLocation}:"
    $found = $false
    if (Test-Path -LiteralPath $KeyLocation -PathType Container) {
        foreach ($file in (Get-ChildItem -LiteralPath $KeyLocation -File -Force | Sort-Object Name)) {
            $reader = $null
            try {
                $reader = [IO.File]::OpenText($file.FullName)
                $firstLine = $reader.ReadLine()
            } catch [UnauthorizedAccessException] { continue }
            catch [IO.IOException] { continue }
            finally { if ($null -ne $reader) { $reader.Dispose() } }
            if ($firstLine -cmatch '^-----BEGIN (?:OPENSSH |RSA |DSA |EC |ENCRYPTED )?PRIVATE KEY-----$') {
                Write-Output $file.FullName
                Test-PrivateKeyAccess $file.FullName
                $found = $true
            }
        }
    }
    if (-not $found) { Write-Output 'No private keys found.' }
}

function Show-Help {
    @'
certKeys <command> [-context name] [-default [true|false]] [-algorithm rsa]
                   [-keybits 2048] [-target user@host|path] [-alias name]
                   [-force [true|false]] [-trace [true|false]]
certKeys -version                 Show installed version and check GitHub.

Commands (case-insensitive):
  createKeys                      Create private, SSH public and PEM public keys.
  createPublicKeys                Regenerate public keys; offer to create missing keys.
  getPublicSSHKey                  Export SSH public key to -target (default: current directory).
  makeKeyAsDefault                Copy all three context key files to id_rsa.*.
  storeKeyAt                      Install public key on -target user@host via SSH.
  createConfigEntry               Add/replace SSH Host entry for -target; optional -alias.
  removeConfigEntry               Remove SSH Host entry by -alias or -target.
  list                            List private key paths in the user's .ssh directory.
                                  Warn about incorrect ownership or Windows ACLs.
  showConfig                      Display the Windows user's SSH configuration.
  syncKeysToWindows               Copy keys/config from other home into Windows profile.
  syncKeysFromWindows             Copy Windows keys/config to other home.
  help                            Show help.

Keys and config: %USERPROFILE%\.ssh. Default context: lowercase computer name.
Sync: use -target <other home directory> or run from that directory (must contain .ssh).
Native Windows PowerShell 5.1+ or PowerShell 7; Windows OpenSSH and OpenSSL on PATH.
storeKeyAt expects a Unix/POSIX SSH server. No local Bash, WSL or ssh-copy-id needed.
'@
}

try {
    $Options = @{}
    $Command = 'help'
    $haveCommand = $false
    for ($i = 0; $i -lt $args.Count; $i++) {
        $item = [string]$args[$i]
        if ($item.StartsWith('-')) {
            $name = $item.Substring(1).ToLowerInvariant()
            if ($name -notin @('version','context','default','algorithm','keybits','target','alias','force','trace')) {
                throw "Unknown parameter: $item"
            }
            $value = '1'
            if ($i + 1 -lt $args.Count -and -not ([string]$args[$i + 1]).StartsWith('-')) {
                $i++; $value = [string]$args[$i]
            }
            $Options[$name] = $value
        } elseif (-not $haveCommand) { $Command = $item; $haveCommand = $true }
        else { throw "Unexpected argument: $item" }
    }
    if ($Options.ContainsKey('version')) { Show-Version; exit 0 }
    Write-Output "Key/Cert Helper Ver.:$Prog_Version (c) 2024 - LSC Labs"
    if ($Command -ieq 'help') { Show-Help; exit 0 }
    if ($env:OS -ne 'Windows_NT') { throw 'Use certKeys.ps1 on Windows; use certKeys on Unix.' }
    $KeyLocation = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.ssh'
    if ($Command -ieq 'list') { Show-PrivateKeys; exit 0 }
    $ConfigFile = Join-Path $KeyLocation 'config'
    $Algorithm = 'rsa'
    if ($Options['algorithm']) { $Algorithm = ([string]$Options['algorithm']).ToLowerInvariant() }
    # The Bash edition's OpenSSL rsa_keygen_bits option currently supports RSA only.
    if ($Algorithm -ne 'rsa') { throw 'Supported key algorithm: rsa.' }
    $KeyBits = '2048'
    if ($Options['keybits']) { $KeyBits = [string]$Options['keybits'] }
    if ($KeyBits -notmatch '^\d+$' -or [int]$KeyBits -lt 1024) { throw 'Use an RSA key size of at least 1024 bits.' }
    $context = $env:COMPUTERNAME.ToLowerInvariant()
    if ($Options.ContainsKey('context')) {
        $context = [string]$Options['context']
        if ($context -eq '1') { $context = '' }
    }
    if ($context -and $context -notmatch '^[a-zA-Z0-9_.-]+$') { throw 'Use a context without whitespace or path separators.' }
    $KeyName = "id@${context}_$Algorithm"
    if (Test-TrueValue $Options['default']) { $KeyName = "id_$Algorithm" }
    $PrivateKey = Join-Path $KeyLocation $KeyName
    $DefaultKey = Join-Path $KeyLocation "id_$Algorithm"
    switch ($Command.ToLowerInvariant()) {
        'createkeys' { New-KeyPair }
        'createpublickeys' { New-PublicKeys }
        'makekeyasdefault' { Copy-DefaultKeys }
        'getpublicsshkey' {
            $destination = '.'
            if ($Options['target']) { $destination = [string]$Options['target'] }
            Copy-Item -LiteralPath "$PrivateKey.pub" -Destination $destination -Force
        }
        'storekeyat' { Send-PublicKey }
        'createconfigentry' { Add-ConfigEntry }
        'removeconfigentry' { Remove-ConfigEntry }
        'showconfig' { Get-Content -LiteralPath $ConfigFile }
        'synckeystowindows' { Sync-Keys $true }
        'synckeysfromwindows' { Sync-Keys $false }
        default { throw "Unknown command: $Command" }
    }
} catch {
    [Console]::Error.WriteLine('[E] ' + $_.Exception.Message)
    exit 1
}

# certKeys

Language / Sprache: **English** | [Deutsch](README.de.md)

`certKeys` creates private and public SSH keys, manages entries in
`~/.ssh/config`, and transfers public keys to SSH servers. On Windows, it can
also synchronise keys and configuration between a Unix shell and the Windows
user directory.

## Native Windows edition (PowerShell)

`certKeys.ps1` runs in Windows PowerShell 5.1 or PowerShell 7 without Bash,
Git Bash, Cygwin, or WSL. Install Windows OpenSSH Client (`ssh.exe` and
`ssh-keygen.exe`) and native OpenSSL (`openssl.exe`) and make them available on
`PATH`. OpenSSL is needed for key creation and PEM export. The update check uses
PowerShell's HTTP client and does not require `curl`.

For a release that includes the Windows edition, download **`certKeys.ps1` and
`certKeys.bat`** from its release assets and keep them in the same directory.
The build produces both files; attach each as an individual download when
publishing the Windows release. Install into the current user's application
directory in PowerShell:

```powershell
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\certKeys'
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
foreach ($file in @('certKeys.ps1', 'certKeys.bat')) {
    Invoke-WebRequest -UseBasicParsing `
        -Uri "https://github.com/LSC-Labs/certKeys/releases/latest/download/$file" `
        -OutFile (Join-Path $installDir $file)
    Unblock-File -LiteralPath (Join-Path $installDir $file)
}
$userPath = [string][Environment]::GetEnvironmentVariable('Path', 'User')
if ($installDir -notin ($userPath -split ';')) {
    [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $installDir), 'User')
}
$env:Path = $installDir + ';' + $env:Path
certKeys.bat help
certKeys.bat -version
```

Then run directly in a newly opened **cmd.exe**:

```bat
certKeys help
certKeys list
certKeys -version
```

`certKeys.bat` starts Windows PowerShell with `-NoLogo -NoProfile
-ExecutionPolicy Bypass -File`, locates `certKeys.ps1` beside itself, forwards
arguments and returns PowerShell's exit code. The execution policy applies only
to this process; user and system settings remain unchanged. Group Policy can
still restrict execution. Interactive prompts remain available. Installation
needs no administrator rights. In PowerShell, explicitly invoke `certKeys.bat`
so the adjacent `.ps1` is not selected instead. Replace both files when updating.
Direct `.ps1` invocation remains subject to the current PowerShell session's
execution policy.

All commands and parameters documented below also apply to the Windows edition.
It stores keys and `config` in `%USERPROFILE%\.ssh`, uses the lowercase computer
name as the default context, writes UTF-8 files without a BOM, and restricts
private keys and SSH configuration to the current Windows user with Windows ACLs.
RSA keys use `-algorithm rsa` and `-keybits` (default 2048). `-force`, `-default`,
`-trace`, `-alias`, `-target`, and `-version` are supported, including mixed-case
parameter names and explicit boolean values.

```powershell
certKeys createKeys -context work -keybits 4096
certKeys createConfigEntry -context work -target alice@server.example -alias workserver
certKeys getPublicSSHKey -context work -target "$env:USERPROFILE\Desktop"
```

`storeKeyAt` replaces `ssh-copy-id` with native `ssh.exe`: it sends only the
public key to a **Unix/POSIX SSH server** and avoids adding duplicate key lines.
Authentication and host-key confirmation are handled by OpenSSH. Remote Windows
OpenSSH servers with a PowerShell default shell are not supported by this command.

In the native edition, `syncKeysToWindows` copies from a second home directory
into `%USERPROFILE%\.ssh`; `syncKeysFromWindows` copies in the opposite direction.
Specify the other home with `-target`, or run from that home directory. Its `.ssh`
subdirectory must already exist. Files are overwritten and matching Host blocks
are replaced; unrelated destination entries remain. Use a Windows filesystem
that supports Windows ACLs; for WSL's Linux filesystem, run the Bash edition
inside WSL instead.

```powershell
certKeys syncKeysToWindows -target 'D:\UnixHome'
certKeys syncKeysFromWindows -target 'D:\UnixHome'
```

The Bash requirements and Unix-shell installation below apply to the `certKeys`
asset. Native Windows users install `certKeys.ps1` and `certKeys.bat` as described above.

## Requirements and installation

Supported environments are macOS, Debian/Ubuntu Linux, and Unix shells running
under Windows (WSL, MSYS/Git Bash, and Cygwin). Requirements:

- Bash 3.2 or newer;
- OpenSSL for key generation and PEM export;
- `curl` for `-version` update checks;
- OpenSSH with `ssh-keygen`, plus `ssh-copy-id` for `storeKeyAt`;
- standard Unix utilities, including `awk`, `tr`, `mktemp`, `cp`, and `chmod`.

On Debian/Ubuntu, install the runtime dependencies with:

```sh
sudo apt-get update
sudo apt-get install bash openssl openssh-client curl
```

On macOS, no newer Bash installation or GNU sed is required. The required
programs must be available through `PATH`.

## Installation from a release

Download only the bundled `certKeys` file from the latest
[GitHub Release](https://github.com/LSC-Labs/certKeys/releases/latest).
A repository checkout, Python, and the separate library are not needed.
The commands below require `curl` and assume that the release has an asset
named exactly `certKeys`. The build artifact must first be attached to a
published GitHub Release under that name.

Install for the current user in `~/.local/bin`, without administrator rights:

| Platform | Installation location | Shell configuration for `PATH` |
| --- | --- | --- |
| macOS (zsh) | `$HOME/.local/bin/certKeys` | `~/.zprofile` |
| Debian/Ubuntu (Bash), including WSL | `$HOME/.local/bin/certKeys` inside Linux | `~/.profile` |
| Windows with MSYS/Git Bash or Cygwin | `$HOME/.local/bin/certKeys` inside the Unix shell home directory | `~/.bash_profile` |

Run these commands in Terminal on macOS or in the appropriate Unix shell on
Linux/Windows. Under WSL, install inside the Linux distribution; under Git Bash,
MSYS, or Cygwin, use that shell's home directory. Native PowerShell and Command
Prompt cannot execute this Bash script directly.

```sh
(
    set -e
    download_dir=$(mktemp -d)
    trap 'rm -rf "$download_dir"' EXIT
    curl --fail --location --show-error \
        https://github.com/LSC-Labs/certKeys/releases/latest/download/certKeys \
        --output "$download_dir/certKeys"
    mkdir -p "$HOME/.local/bin"
    install -m 755 "$download_dir/certKeys" "$HOME/.local/bin/certKeys"
)
```

Add the following line once to the shell configuration file listed above if
`~/.local/bin` is not already on your `PATH`:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Open a new login shell afterward, or run that `export` command in the current
terminal, then check the installation:

```sh
command -v certKeys
certKeys help
```

All examples below assume this installation. The command also works from zsh;
execute it directly so its Bash shebang selects the interpreter. To update,
repeat the download and installation commands; keys and configuration remain
in `~/.ssh`.

## Release build (development)

Build a standalone executable with Python 3 (needed only for the build):

```sh
python3 scripts/build.py
```

The build embeds `src/LScriptLibV1.sh` into `src/certKeys`, writing the result to `release/certKeys`. Only this generated
file needs to be distributed; the runtime programs listed above are still
required. The build also copies the standalone Windows edition to `release/certKeys.ps1`
and the CMD launcher to `release/certKeys.bat`, and verifies that both script
editions have the same version. The generated `release/`
directory is ignored by Git.

The GitHub Actions workflow **Release build** runs on pushes, pull requests,
and manual dispatch. It builds and tests the executable, then makes it available
as the `certKeys-release` artifact containing all three files for release publication. After downloading
the artifact, run `chmod +x certKeys` if needed. The compatibility workflow also
tests the bundled executable on Linux and macOS.

## Quick start

Create a key pair for the `work` context, transfer it to a server, and then
connect using an SSH alias:

```sh
certKeys createKeys -context work -keybits 4096
certKeys storeKeyAt -context work -target alice@server.example.com -alias workserver
ssh workserver
```

The first command may ask whether to copy the new key to the default key files
as well. `storeKeyAt` authenticates with the target server over SSH and then
offers to create a local configuration entry. If you confirm that prompt, the
`workserver` alias is available for the final command.

## Version and update check

```sh
certKeys -version
```

Prints the installed version and checks the latest published GitHub release.
If a newer version exists, it shows the version and a direct download link for
`certKeys`. Version components are compared numerically. No files are downloaded
or installed automatically; use the installation instructions above to update.

This option requires `curl` and internet access. The connection timeout is five
seconds and the request timeout is ten seconds. If `curl` is missing or the
request fails (including GitHub rate limits), the installed version is still
shown and the command exits with status 1 and an error message. A successful
check exits with status 0, whether or not an update is available. `-version`
takes precedence over other commands and does not modify keys or configuration.

## Invocation and arguments

```text
certKeys <command> [parameters ...]
```

Without a command, the program displays help. Command and parameter names are
case-insensitive. Values such as file paths, context names, and aliases retain
their original case.

Parameters use a single hyphen. Supply each value as a separate argument;
`-context=work` syntax is not supported. Put the command before its parameters:

```sh
certKeys createKeys -context work -algorithm rsa -keybits 4096
```

Quote values containing spaces, such as an export directory:

```sh
certKeys getPublicSSHKey -context work -target "$HOME/Key Export"
```

Use simple context names and SSH aliases without spaces or path separators,
such as `work`, `personal`, or `project-a`.

## Storage locations and key selection

All local keys are stored in `$HOME/.ssh`. The context determines which key pair
a command uses. With RSA and `-context work`, the following files are used:

| File | Contents |
| --- | --- |
| `~/.ssh/id@work_rsa` | Private key |
| `~/.ssh/id@work_rsa.pub` | Public key in SSH format |
| `~/.ssh/id@work_rsa.pub.pem` | Public key in PEM format |
| `~/.ssh/config` | Local SSH configuration with host aliases |

Without `-context`, the lowercase computer name is used. With `-default`, the
selected files are `id_rsa`, `id_rsa.pub`, and `id_rsa.pub.pem` instead; any
additional `-context` parameter is ignored.

The context is not derived from the target server. Subsequent commands must
therefore use the same context that was used to create the key.

## Parameters

### `-context <name>`

Selects a key context. The default is the lowercase computer name. The filename
is `id@<name>_<algorithm>`.

Available with `createKeys`, `createPublicKeys`, `getPublicSSHKey`,
`makeKeyAsDefault`, `storeKeyAt`, and `createConfigEntry`.

```sh
certKeys createKeys -context project-a
certKeys getPublicSSHKey -context project-a -target /tmp
```

Always supply a name. A standalone `-context` does not select the computer name;
it currently results in an empty context in the filename. This parameter has no
effect on `list`, `removeConfigEntry`, `showConfig`, or the synchronisation commands.

### `-default [1|0]`

Selects the default key `id_<algorithm>` instead of a context key. Without a
value, `-default` is equivalent to `1`; the option is disabled by default.
`-default 0` restores context-based selection.

```sh
certKeys createKeys -default
certKeys createPublicKeys -default
certKeys storeKeyAt -default -target alice@server.example.com
```

This option applies to the same six commands as `-context`. It does not copy an
existing context key; use `makeKeyAsDefault` for that purpose.

### `-algorithm <algorithm>`

Sets the algorithm and the corresponding part of the filename. The default is
`rsa`. Use RSA with the current implementation: key generation always passes
the RSA option `rsa_keygen_bits` to OpenSSL. Other algorithms are therefore not
generally supported at present.

```sh
certKeys createKeys -context work -algorithm rsa
```

This parameter applies to key selection commands in the same way as `-context`.

### `-keybits <bits>`

Sets the key length when generating a private RSA key. The default is `2048`.
The value is passed to OpenSSL.

```sh
certKeys createKeys -context work -keybits 4096
```

Applies to `createKeys`, and when `createPublicKeys` or `storeKeyAt` generates a
missing private key. This parameter alone does not change an existing private
key.

### `-force [1|0]`

Skips the confirmation prompt in `createKeys` before replacing an existing
private key. Without a value, `-force` is equivalent to `1`; the option is
disabled by default.

```sh
certKeys createKeys -context test -force -keybits 4096
```

This generates a new key pair. Public keys already installed on servers are not
updated automatically. `-force` does not confirm other prompts, such as copying
the key to the default files or creating an SSH configuration entry.

### `-target <target>`

Its meaning depends on the command:

| Command | Meaning of `-target` |
| --- | --- |
| `getPublicSSHKey` | Local export directory or destination file; defaults to the current directory |
| `storeKeyAt` | SSH destination, usually `user@hostname`; required |
| `createConfigEntry` | Hostname or `user@hostname` to store in the SSH entry |
| `removeConfigEntry` | Target from which to derive the alias to remove when `-alias` is omitted |

```sh
certKeys getPublicSSHKey -context work -target /tmp
certKeys createConfigEntry -context work -target alice@server.example.com
```

An export directory must already exist. If the target is not an existing
directory, `cp` treats it as a filename. `-target` is not a general option for
changing the local key directory, which remains `$HOME/.ssh`.

### `-alias <name>`

Sets the name of a `Host` entry in `~/.ssh/config`. Applies to
`createConfigEntry`, `removeConfigEntry`, and the optional configuration step in
`storeKeyAt`.

Without `-alias`, the alias derived from `alice@server.example.com` is `server`.
An IPv4 address is used in full as the alias.

```sh
certKeys createConfigEntry -context work -target alice@server.example.com -alias work-ssh
ssh work-ssh
```

An alias does not select a key context. Also supply the appropriate value of
`-context` or use `-default`.

### `-trace [1|0]`

Enables additional diagnostic output on standard error. Without a value,
`-trace` is equivalent to `1`; diagnostic output is disabled by default.

```sh
certKeys createConfigEntry -context work -target alice@server.example.com -trace
```

The boolean parameters `-default`, `-force`, and `-trace` accept, among other
values, `1`/`true` to enable them and `0`/`false` to disable them.

## Commands

### `list` – List private keys

```sh
certKeys list
```

Lists the full paths of readable private key files directly in the user's SSH
directory: `$HOME/.ssh` in the Bash edition, `%USERPROFILE%\.ssh` in the native
Windows edition. Both default and context keys are listed, including custom
filenames and hidden files. `-context`, `-default`, and `-algorithm` do not filter
the list.

Files are identified by their first-line OpenSSH or PEM private-key header
(OpenSSH, RSA, DSA, EC, PKCS#8, or encrypted PKCS#8); encrypted keys are included
without asking for a passphrase. The command lists paths only, never key contents,
and does not validate or decrypt the keys. Public keys, SSH configuration and
other files without a recognized header are omitted. Subdirectories are not
searched. A missing or empty SSH directory produces `No private keys found.`
and is not created or modified. No additional cryptographic tools are required.

For each recognized key, `list` also checks its permissions. On Unix, the key
must belong to the current user and have mode `400` or `600`; macOS ACL grants
are flagged separately. On Windows, the owner must be the current user, ACL
inheritance must be disabled, and access grants may name only that user,
`SYSTEM`, or the built-in Administrators group. Other grants are flagged for
review, including inherited rules; deny rules do not suppress this warning.

Warnings on standard error identify the affected file and explain the issue.
If permissions cannot be inspected, the command reports that as a warning too.
It continues listing other keys and exits successfully despite these warnings.
It does not change ownership or permissions. On Unix, check ownership and use
`chmod 600 /path/to/private-key` as appropriate; inspect macOS ACLs with `ls -le`.
On Windows, review the file's Security settings or use `icacls` to restrict
access. Only readable files with a recognized header are checked; unreadable
files cannot be identified as private keys and are omitted.

### `help` – Display help

```sh
certKeys help
certKeys
```

Displays the available commands and brief option descriptions.
`syncKeysToWindows` and `syncKeysFromWindows` are listed only in Unix shells
running under Windows.

### `createKeys` – Create a key pair

```sh
certKeys createKeys -context work -keybits 4096
certKeys createKeys -default -keybits 4096
```

Generates a private RSA key and public keys in PEM and SSH formats. If `~/.ssh`
is missing, it is created with permissions `700`; the private key receives
permissions `600`. The newly generated private key is stored without a
passphrase.

If the selected private key already exists, the program asks whether to
overwrite it. Pressing Enter confirms this prompt with `Y`. `-force` skips the
prompt.

If the default key is missing, the program then offers to copy the new key pair
to the default filenames as well. This prompt also defaults to `Y`.

Parameters: `-context`, `-default`, `-algorithm`, `-keybits`, `-force`, `-trace`.

### `createPublicKeys` – Regenerate public keys

```sh
certKeys createPublicKeys -context work
certKeys createPublicKeys -default
```

Derives the `.pub` and `.pub.pem` files again from the selected private key.
Existing public files are replaced; the private key is unchanged. This is
useful, for example, after losing a public key file.

If the private key is missing, the program runs the `createKeys` procedure
instead, including its confirmation prompts.

Parameters: `-context`, `-default`, `-algorithm`, `-trace`; `-keybits` when a
private key needs to be generated.

### `getPublicSSHKey` – Export a public SSH key

```sh
certKeys getPublicSSHKey -context work
certKeys getPublicSSHKey -context work -target /tmp
certKeys getPublicSSHKey -default -target /tmp/my-key.pub
```

Copies only the public `.pub` file. Without `-target`, it is copied to the
current working directory. An existing destination directory receives a file
with the original name; a destination file path can rename the export.
Existing destination files may be replaced by `cp`.

Neither the private key nor the PEM export is copied. If the public SSH file
is missing, a message is displayed; this command does not generate it.

Parameters: `-context`, `-default`, `-algorithm`, `-target`, `-trace`.

### `makeKeyAsDefault` – Use a context key as the default

```sh
certKeys makeKeyAsDefault -context work
```

Copies the selected private key and both public files to the default filenames:
for RSA, these are `id_rsa`, `id_rsa.pub`, and `id_rsa.pub.pem`. All three source
files must exist.

Existing default files are replaced without confirmation; `-force` is not
required. The context files are retained. If `-default` is already selected,
no copy is needed and no change is made.

Parameters: `-context`, `-default`, `-algorithm`, `-trace`.

### `storeKeyAt` – Transfer a public key to a server

```sh
certKeys storeKeyAt -context work -target alice@server.example.com -alias workserver
```

Transfers the selected public SSH key to the target using `ssh-copy-id`.
Authentication may require a password or another SSH authentication method.
The private key stays on the local machine.

If the public SSH file is missing, the program first asks whether to generate
it; the default is `N`. If the private key is also missing, a further prompt
asks whether to generate it.

After the transfer command, the program asks whether to create a local SSH
entry; the default is `Y`. If confirmed, `createConfigEntry` is called with the
selected target, context, and alias. You can then connect using, for example,
`ssh workserver`.

Parameters: `-target`, `-context`, `-default`, `-algorithm`, `-alias`, `-trace`;
`-keybits` when a private key needs to be generated.

### `createConfigEntry` – Create or replace an SSH alias

```sh
certKeys createConfigEntry -context work -target alice@server.example.com -alias workserver
```

Writes an entry to `~/.ssh/config`, for example:

```sshconfig
Host workserver
     HostName      server.example.com
     IdentityFile  ~/.ssh/id@work_rsa
     User          alice
```

If the same alias already exists, its previous block is removed without
confirmation and the new entry is appended. Other entries are retained. The
key does not need to exist yet; this command does not generate or transfer keys.

For a target without `user@`, such as `server.example.com`, no `User` value is
written. SSH determines the user from its other settings or the local username.

Parameters: `-target`, `-alias`, `-context`, `-default`, `-algorithm`, `-trace`.

### `removeConfigEntry` – Remove an SSH alias

```sh
certKeys removeConfigEntry -alias workserver
certKeys removeConfigEntry -target alice@server.example.com
```

Removes the `Host` block belonging to the alias from `~/.ssh/config`. In the
second example, the alias `server` is derived from the target. For a custom
alias, supply `-alias` instead.

Key files and public keys installed on servers are not deleted. There is no
confirmation prompt. `-context` has no effect here because the entry is selected
solely by its alias.

Parameters: `-alias` or `-target`, optionally `-trace`.

### `showConfig` – Display SSH configuration

```sh
certKeys showConfig
```

Prints the entire `~/.ssh/config` file. There is no selection by context or
alias. If the file is missing, `cat` reports an error.

### `syncKeysToWindows` – Copy Unix keys to Windows

Available only under WSL, MSYS/Git Bash, and Cygwin. On macOS and native Linux,
the command is hidden from help and direct invocation is rejected.

Run the command from the Windows user directory, which must already contain a
`.ssh` subdirectory. Adjust the example program path to match its actual
location:

```sh
# WSL example: use the Windows profile as the working directory.
cd /mnt/c/Users/MyName
certKeys syncKeysToWindows
```

Copies all regular files whose names start with `id` from `$HOME/.ssh` to
`./.ssh`. This includes private and public keys for all contexts, as well as
default files. Existing destination files with the same names are replaced
without confirmation.

The `Host` entries from the Unix configuration are merged into `./.ssh/config`.
Destination blocks with matching aliases are replaced; additional destination
entries are retained. This synchronises host entries rather than copying all
global SSH settings.

`-context`, `-default`, and `-target` do not select a subset or different
directories here. The Windows destination is always `.ssh` in the working
directory. This command does not configure Windows file permissions.

### `syncKeysFromWindows` – Copy Windows keys to Unix

Also available only in Unix shells running under Windows. The working
directory and invocation follow the same pattern as the previous command:

```sh
cd /mnt/c/Users/MyName
certKeys syncKeysFromWindows
```

Copies all regular files whose names start with `id` from `./.ssh` to
`$HOME/.ssh`. Missing local key directories are created. Key files receive
permissions `600`; files with `pub` in their names then receive `644`.

Host entries from `./.ssh/config` are merged into the local configuration.
Matching local alias blocks and key files with the same names are replaced
without confirmation. Additional local files and host entries are not deleted.

Here too, `-context`, `-default`, and `-target` do not filter files or select
paths. In MSYS/Git Bash and Cygwin, use the Windows profile path valid in that
shell instead of the WSL path. `$HOME/.ssh` and `./.ssh` must be different
directories. In Git Bash in particular, `$HOME` may already be the Windows
profile, leaving no separate set of keys to synchronise.

## Testing and development

The compatibility tests additionally require Python 3:

```sh
python3 tests/test_compatibility.py
```

They use a temporary user directory, do not change personal SSH keys, and do not
contact a server. Checks include key generation, context selection, default
copies, export, SSH configuration, and synchronisation. Operating system
detection is tested using simulated environments.

The GitHub Actions workflow is configured for Debian 12/13, Ubuntu 22.04/24.04,
and macOS. The Linux containers also check execution with their respective
Linux system utilities.

# certKeys

Sprache / Language: [English](README.md) | **Deutsch**

`certKeys` erstellt private und öffentliche SSH-Schlüssel, verwaltet Einträge in
`~/.ssh/config` und überträgt öffentliche Schlüssel auf SSH-Server. Unter Windows
können außerdem Schlüssel und Konfiguration zwischen einer Unix-Shell und dem
Windows-Benutzerverzeichnis abgeglichen werden.

## Native Windows-Variante (PowerShell)

`certKeys.ps1` läuft unter Windows PowerShell 5.1 oder PowerShell 7 ohne Bash,
Git Bash, Cygwin oder WSL. Benötigt werden der Windows-OpenSSH-Client (`ssh.exe`
und `ssh-keygen.exe`) sowie natives OpenSSL (`openssl.exe`) im `PATH`. OpenSSL
wird zur Schlüsselerzeugung und zum PEM-Export benötigt. Die Updateprüfung
verwendet den HTTP-Client von PowerShell und benötigt kein `curl`.

Bei einem Release mit Windows-Variante **`certKeys.ps1` und `certKeys.bat`** aus
dessen Release-Assets herunterladen und im selben Verzeichnis ablegen. Der Build
erzeugt beide Dateien; bei der Veröffentlichung werden sie als einzelne Downloads
an das Windows-Release angehängt. In PowerShell in das Anwendungsverzeichnis des
aktuellen Benutzers installieren:

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

Danach funktioniert der direkte Aufruf in einer neu geöffneten **cmd.exe**:

```bat
certKeys help
certKeys list
certKeys -version
```

`certKeys.bat` startet Windows PowerShell mit `-NoLogo -NoProfile
-ExecutionPolicy Bypass -File`, findet `certKeys.ps1` relativ zum eigenen
Verzeichnis, reicht die Argumente weiter und gibt den PowerShell-Exitcode zurück.
Die Ausführungsrichtlinie wird nur für diesen Prozess gesetzt; Benutzer- und
Systemeinstellungen werden nicht verändert. Gruppenrichtlinien können die
Ausführung weiterhin einschränken. Interaktive Rückfragen bleiben verfügbar.
Die Installation benötigt keine Administratorrechte. In PowerShell den Starter
explizit als `certKeys.bat` aufrufen, damit die direkt daneben liegende `.ps1`
nicht stattdessen ausgewählt wird. Bei Aktualisierungen beide Dateien ersetzen.
Für das direkte Ausführen der `.ps1` gelten weiterhin die Ausführungsrichtlinien
der jeweiligen PowerShell-Sitzung.

Alle unten dokumentierten Befehle und Parameter gelten auch für die Windows-Variante.
Schlüssel und `config` liegen unter `%USERPROFILE%\.ssh`; der Standardkontext ist
der Computername in Kleinbuchstaben. Die Dateien werden als UTF-8 ohne BOM
angelegt. Private Schlüssel und SSH-Konfiguration erhalten Windows-ACLs, die nur
dem aktuellen Benutzer Zugriff gewähren. RSA-Schlüssel verwenden `-algorithm rsa`
und `-keybits` (Standard 2048). `-force`, `-default`, `-trace`, `-alias`, `-target`
und `-version` werden unterstützt, auch mit gemischter Groß-/Kleinschreibung der
Parameternamen und expliziten booleschen Werten.

```powershell
certKeys createKeys -context arbeit -keybits 4096
certKeys createConfigEntry -context arbeit -target alice@server.example -alias arbeitsserver
certKeys getPublicSSHKey -context arbeit -target "$env:USERPROFILE\Desktop"
```

`storeKeyAt` ersetzt `ssh-copy-id` durch natives `ssh.exe`: Nur der öffentliche
Schlüssel wird an einen **Unix/POSIX-SSH-Server** übertragen; doppelte
Schlüsselzeilen werden vermieden. Anmeldung und Hostschlüsselbestätigung übernimmt
OpenSSH. Windows-OpenSSH-Zielserver mit PowerShell als Standardshell werden von
diesem Befehl nicht unterstützt.

In der nativen Variante kopiert `syncKeysToWindows` aus einem zweiten
Home-Verzeichnis nach `%USERPROFILE%\.ssh`; `syncKeysFromWindows` kopiert in die
Gegenrichtung. Das andere Home mit `-target` angeben oder aus diesem Verzeichnis
aufrufen. Dessen Unterverzeichnis `.ssh` muss bereits existieren. Dateien werden
überschrieben und passende Host-Blöcke ersetzt; andere Zieleinträge bleiben
erhalten. Ein Windows-Dateisystem mit Windows-ACL-Unterstützung verwenden; für
das Linux-Dateisystem von WSL stattdessen die Bash-Variante innerhalb von WSL nutzen.

```powershell
certKeys syncKeysToWindows -target 'D:\UnixHome'
certKeys syncKeysFromWindows -target 'D:\UnixHome'
```

Die folgenden Bash-Voraussetzungen und die Unix-Shell-Installation beziehen sich
auf das Asset `certKeys`. Für natives PowerShell gilt die obige Installation von
`certKeys.ps1` und `certKeys.bat`.

## Voraussetzungen und Installation

Unterstützt werden macOS, Debian/Ubuntu Linux sowie Unix-Shells unter Windows
(WSL, MSYS/Git Bash und Cygwin). Benötigt werden:

- Bash ab Version 3.2;
- OpenSSL zur Schlüsselerzeugung und zum PEM-Export;
- `curl` für die Updateprüfung mit `-version`;
- OpenSSH mit `ssh-keygen` und für `storeKeyAt` zusätzlich `ssh-copy-id`;
- die üblichen Unix-Werkzeuge, unter anderem `awk`, `tr`, `mktemp`, `cp` und `chmod`.

Unter Debian/Ubuntu lassen sich die Laufzeitabhängigkeiten so installieren:

```sh
sudo apt-get update
sudo apt-get install bash openssl openssh-client curl
```

Unter macOS ist keine neuere Bash und kein GNU sed erforderlich. Die benötigten
Programme müssen über `PATH` erreichbar sein.

## Installation aus einem Release

Nur die gebündelte Datei `certKeys` aus dem neuesten
[GitHub-Release](https://github.com/LSC-Labs/certKeys/releases/latest)
herunterladen. Ein Repository-Checkout, Python und die separate Bibliothek
werden nicht benötigt. Die folgenden Befehle benötigen `curl` und setzen ein
Release-Asset mit dem exakten Namen `certKeys` voraus. Das Build-Artefakt muss
zuerst unter diesem Namen an ein veröffentlichtes GitHub-Release angehängt werden.

Die Installation erfolgt für den aktuellen Benutzer unter `~/.local/bin`, ohne
Administratorrechte:

| Plattform | Installationsort | Shell-Konfiguration für `PATH` |
| --- | --- | --- |
| macOS (zsh) | `$HOME/.local/bin/certKeys` | `~/.zprofile` |
| Debian/Ubuntu (Bash), einschließlich WSL | `$HOME/.local/bin/certKeys` innerhalb von Linux | `~/.profile` |
| Windows mit MSYS/Git Bash oder Cygwin | `$HOME/.local/bin/certKeys` im Home-Verzeichnis der Unix-Shell | `~/.bash_profile` |

Die folgenden Befehle unter macOS im Terminal und unter Linux/Windows in der
jeweiligen Unix-Shell ausführen. Unter WSL innerhalb der Linux-Distribution
installieren; unter Git Bash, MSYS oder Cygwin das Home-Verzeichnis dieser Shell
verwenden. Native PowerShell und Eingabeaufforderung können das Bash-Skript
nicht direkt ausführen.

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

Falls `~/.local/bin` noch nicht im `PATH` enthalten ist, folgende Zeile einmalig
in die oben angegebene Shell-Konfigurationsdatei eintragen:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Anschließend eine neue Login-Shell öffnen oder den `export`-Befehl im aktuellen
Terminal ausführen und die Installation prüfen:

```sh
command -v certKeys
certKeys help
```

Alle folgenden Beispiele setzen diese Installation voraus. Der Aufruf funktioniert
auch aus zsh; beim direkten Ausführen wählt die Bash-Shebang den Interpreter.
Für ein Update die Download- und Installationsbefehle erneut ausführen; Schlüssel
und Konfiguration bleiben unter `~/.ssh` erhalten.

## Release-Build (Entwicklung)

Mit Python 3 (nur für den Build benötigt) eine eigenständige Datei erstellen:

```sh
python3 scripts/build.py
```

Der Build bettet `src/LScriptLibV1.sh` in `src/certKeys` ein und schreibt das
Ergebnis nach `release/certKeys`. Für die Weitergabe
wird nur diese erzeugte Datei benötigt; die oben genannten Laufzeitprogramme
bleiben erforderlich. Der Build kopiert außerdem die eigenständige Windows-Variante nach
`release/certKeys.ps1` und den CMD-Starter nach `release/certKeys.bat`; außerdem
prüft er, dass beide Skriptvarianten dieselbe Version haben.
Das erzeugte Verzeichnis `release/` wird von Git ignoriert.

Der GitHub-Actions-Workflow **Release build** läuft bei Pushes, Pull Requests
und manueller Ausführung. Er baut und testet die Datei und stellt sie anschließend
als Artefakt `certKeys-release` mit allen drei Dateien für die Releaseveröffentlichung bereit. Nach dem
Herunterladen des Artefakts gegebenenfalls `chmod +x certKeys` ausführen. Der
Kompatibilitätsworkflow testet die gebündelte Datei zusätzlich unter Linux und
macOS.

## Schnellstart

Ein eigenes Schlüsselpaar für den Kontext `arbeit` erstellen, auf einen Server
übertragen und anschließend über einen SSH-Alias verwenden:

```sh
certKeys createKeys -context arbeit -keybits 4096
certKeys storeKeyAt -context arbeit -target alice@server.example.com -alias arbeitsserver
ssh arbeitsserver
```

Beim ersten Aufruf fragt das Programm gegebenenfalls, ob der neue Schlüssel auch
als Standardschlüssel kopiert werden soll. Bei `storeKeyAt` erfolgt die Anmeldung
am Zielserver über SSH; anschließend kann ein lokaler Konfigurationseintrag
angelegt werden. Wird diese Rückfrage bestätigt, ist der Alias `arbeitsserver`
für den letzten Befehl verfügbar.

## Version und Updateprüfung

```sh
certKeys -version
```

Zeigt die installierte Version an und prüft das neueste veröffentlichte
GitHub-Release. Bei einer neueren Version werden die Versionsnummer und ein
direkter Download-Link für `certKeys` angezeigt. Die Versionsbestandteile werden
numerisch verglichen. Es erfolgt kein automatischer Download und keine
Installation; zum Aktualisieren die Installationsanleitung oben verwenden.

Diese Option benötigt `curl` und Internetzugang. Der Verbindungsaufbau ist auf
fünf Sekunden, die gesamte Anfrage auf zehn Sekunden begrenzt. Fehlt `curl` oder
schlägt die Anfrage fehl (auch bei GitHub-Ratenbegrenzung), wird die installierte
Version trotzdem angezeigt; der Befehl endet mit Status 1 und einer Fehlermeldung.
Eine erfolgreiche Prüfung endet mit Status 0, unabhängig davon, ob ein Update
vorliegt. `-version` hat Vorrang vor anderen Befehlen und verändert weder
Schlüssel noch Konfiguration.

## Aufruf und Argumente

```text
certKeys <Befehl> [Parameter ...]
```

Ohne Befehl wird die Hilfe angezeigt. Befehlsnamen und Parameternamen werden ohne
Beachtung der Groß-/Kleinschreibung ausgewertet. Werte wie Dateipfade, Kontextnamen
und Aliase behalten ihre Schreibweise.

Parameter verwenden einen einzelnen Bindestrich. Ein Wert folgt als eigenes
Argument; die Schreibweise `-context=arbeit` wird nicht unterstützt. Der Befehl
sollte vor den Parametern stehen:

```sh
certKeys createKeys -context arbeit -algorithm rsa -keybits 4096
```

Werte mit Leerzeichen müssen in Anführungszeichen stehen, beispielsweise ein
Exportverzeichnis:

```sh
certKeys getPublicSSHKey -context arbeit -target "$HOME/Key Export"
```

Für Kontextnamen und SSH-Aliase einfache Namen ohne Leerzeichen oder
Pfadtrennzeichen verwenden, etwa `arbeit`, `privat` oder `projekt-a`.

## Speicherorte und Schlüsselauswahl

Alle lokalen Schlüssel liegen in `$HOME/.ssh`. Der Kontext bestimmt, welches
Schlüsselpaar ein Befehl verwendet. Bei RSA und `-context arbeit` entstehen:

| Datei | Inhalt |
| --- | --- |
| `~/.ssh/id@arbeit_rsa` | Privater Schlüssel |
| `~/.ssh/id@arbeit_rsa.pub` | Öffentlicher Schlüssel im SSH-Format |
| `~/.ssh/id@arbeit_rsa.pub.pem` | Öffentlicher Schlüssel im PEM-Format |
| `~/.ssh/config` | Lokale SSH-Konfiguration mit Host-Aliasen |

Ohne `-context` wird der kleingeschriebene Rechnername verwendet. Mit `-default`
werden stattdessen `id_rsa`, `id_rsa.pub` und `id_rsa.pub.pem` ausgewählt; ein
zusätzlich angegebenes `-context` wird dann ignoriert.

Der Kontext wird nicht aus dem Zielserver abgeleitet. Bei späteren Aufrufen muss
also derselbe Kontext verwendet werden, mit dem der Schlüssel erstellt wurde.

## Parameter

### `-context <Name>`

Wählt den Kontext eines Schlüssels aus. Standard ist der Rechnername in
Kleinschreibung. Der Dateiname lautet `id@<Name>_<Algorithmus>`.

Verwendbar mit `createKeys`, `createPublicKeys`, `getPublicSSHKey`,
`makeKeyAsDefault`, `storeKeyAt` und `createConfigEntry`.

```sh
certKeys createKeys -context projekt-a
certKeys getPublicSSHKey -context projekt-a -target /tmp
```

Immer einen Namen angeben. Ein alleinstehendes `-context` wählt keinen
Rechnernamen aus, sondern führt derzeit zu einem leeren Kontext im Dateinamen.
Bei `list`, `removeConfigEntry`, `showConfig` und den Synchronisierungsbefehlen hat dieser
Parameter keine Wirkung.

### `-default [1|0]`

Wählt den Standardschlüssel `id_<Algorithmus>` statt eines Kontextschlüssels aus.
Ohne Parameterwert entspricht `-default` dem Wert `1`; standardmäßig ist die
Option ausgeschaltet. Mit `-default 0` wird wieder die Kontextauswahl verwendet.

```sh
certKeys createKeys -default
certKeys createPublicKeys -default
certKeys storeKeyAt -default -target alice@server.example.com
```

Die Option ist bei denselben sechs Befehlen wie `-context` wirksam. Sie kopiert
keinen bestehenden Kontextschlüssel: Dafür gibt es `makeKeyAsDefault`.

### `-algorithm <Algorithmus>`

Bestimmt den Algorithmus und den entsprechenden Teil des Dateinamens.
Standard ist `rsa`. Für die aktuelle Implementierung ist RSA zu verwenden:
Die Erzeugung übergibt an OpenSSL stets die RSA-Option `rsa_keygen_bits`.
Andere Algorithmen sind deshalb derzeit nicht allgemein unterstützt.

```sh
certKeys createKeys -context arbeit -algorithm rsa
```

Der Parameter wirkt bei den Befehlen zur Schlüsselauswahl wie `-context`.

### `-keybits <Bitanzahl>`

Legt bei der Erzeugung eines privaten RSA-Schlüssels die Schlüssellänge fest.
Standard ist `2048`. Der Wert wird an OpenSSL weitergereicht.

```sh
certKeys createKeys -context arbeit -keybits 4096
```

Wirksam bei `createKeys` sowie dann, wenn `createPublicKeys` oder `storeKeyAt`
einen fehlenden privaten Schlüssel neu erzeugen. Ein vorhandener privater
Schlüssel wird durch diesen Parameter allein nicht verändert.

### `-force [1|0]`

Überspringt bei `createKeys` die Rückfrage vor dem Ersetzen eines vorhandenen
privaten Schlüssels. Ohne Wert entspricht `-force` dem Wert `1`; standardmäßig
ist die Option ausgeschaltet.

```sh
certKeys createKeys -context test -force -keybits 4096
```

Dabei wird ein neues Schlüsselpaar erzeugt. Bereits auf Servern hinterlegte
öffentliche Schlüssel werden nicht automatisch aktualisiert. `-force` bestätigt
keine anderen Rückfragen, etwa zur Übernahme als Standardschlüssel oder zum
Anlegen eines SSH-Konfigurationseintrags.

### `-target <Ziel>`

Die Bedeutung hängt vom Befehl ab:

| Befehl | Bedeutung von `-target` |
| --- | --- |
| `getPublicSSHKey` | Lokales Exportverzeichnis oder Zieldatei; Standard ist das aktuelle Verzeichnis |
| `storeKeyAt` | SSH-Ziel, üblicherweise `benutzer@hostname`; erforderlich |
| `createConfigEntry` | Hostname oder `benutzer@hostname`, der im SSH-Eintrag hinterlegt wird |
| `removeConfigEntry` | Ziel, aus dem ohne `-alias` der zu entfernende Alias abgeleitet wird |

```sh
certKeys getPublicSSHKey -context arbeit -target /tmp
certKeys createConfigEntry -context arbeit -target alice@server.example.com
```

Ein Exportverzeichnis muss bereits existieren. Ist das Ziel kein vorhandenes
Verzeichnis, behandelt `cp` es als Dateinamen. `-target` ist kein allgemeiner
Schalter für das lokale Schlüsselverzeichnis; dieses bleibt `$HOME/.ssh`.

### `-alias <Name>`

Legt den Namen eines `Host`-Eintrags in `~/.ssh/config` fest. Wirksam bei
`createConfigEntry`, `removeConfigEntry` und bei der optionalen Konfiguration
durch `storeKeyAt`.

Ohne `-alias` wird aus `alice@server.example.com` der Alias `server` abgeleitet.
Eine IPv4-Adresse wird vollständig als Alias übernommen.

```sh
certKeys createConfigEntry -context arbeit -target alice@server.example.com -alias arbeit-ssh
ssh arbeit-ssh
```

Ein Alias wählt keinen Schlüsselkontext aus. Dafür muss zusätzlich der passende
Wert von `-context` oder `-default` angegeben werden.

### `-trace [1|0]`

Aktiviert zusätzliche Diagnoseausgaben auf dem Standardfehlerkanal. Ohne Wert
entspricht `-trace` dem Wert `1`; standardmäßig ist die Ausgabe deaktiviert.

```sh
certKeys createConfigEntry -context arbeit -target alice@server.example.com -trace
```

Die booleschen Parameter `-default`, `-force` und `-trace` akzeptieren unter
anderem `1`/`true` zum Einschalten und `0`/`false` zum Ausschalten.

## Befehle

### `list` – Private Schlüssel auflisten

```sh
certKeys list
```

Listet die vollständigen Pfade lesbarer privater Schlüsseldateien direkt im
SSH-Verzeichnis des Benutzers auf: `$HOME/.ssh` in der Bash-Variante,
`%USERPROFILE%\.ssh` in der nativen Windows-Variante. Standard- und
Kontextschlüssel werden ebenso erfasst wie eigene Dateinamen und versteckte
Dateien. `-context`, `-default` und `-algorithm` filtern die Liste nicht.

Die Erkennung erfolgt anhand der ersten Zeile mit einem OpenSSH- oder
PEM-Private-Key-Header (OpenSSH, RSA, DSA, EC, PKCS#8 oder verschlüsseltes PKCS#8).
Auch verschlüsselte Schlüssel erscheinen ohne Passwortabfrage. Ausgegeben werden
nur Pfade, niemals Schlüsselinhalte; die Schlüssel werden weder validiert noch
entschlüsselt. Öffentliche Schlüssel, SSH-Konfiguration und andere Dateien ohne
passenden Header werden ausgelassen. Unterverzeichnisse werden nicht durchsucht.
Bei fehlendem oder leerem SSH-Verzeichnis erscheint `No private keys found.`;
das Verzeichnis wird weder erstellt noch verändert. Zusätzliche
Kryptografieprogramme werden dafür nicht benötigt.

Für jeden erkannten Schlüssel prüft `list` außerdem die Berechtigungen. Unter
Unix muss die Datei dem aktuellen Benutzer gehören und den Modus `400` oder
`600` haben; zusätzliche macOS-ACL-Freigaben werden gesondert gemeldet. Unter
Windows muss der aktuelle Benutzer Besitzer sein, die ACL-Vererbung muss
deaktiviert sein, und Zugriffsfreigaben dürfen nur den Benutzer selbst,
`SYSTEM` oder die integrierte Administratorengruppe betreffen. Andere Freigaben
werden zur Prüfung gemeldet, auch geerbte Regeln; Verweigerungsregeln unterdrücken
diese Warnung nicht.

Warnungen auf der Standardfehlerausgabe nennen den betroffenen Pfad und die
Ursache. Auch wenn die Rechte nicht geprüft werden können, erscheint eine
Warnung. Die Auflistung wird fortgesetzt und endet trotz dieser Warnungen mit
Erfolg. Besitzer und Berechtigungen werden nicht verändert. Unter Unix den
Besitzer prüfen und gegebenenfalls `chmod 600 /pfad/zum/privaten-schluessel`
verwenden; macOS-ACLs lassen sich mit `ls -le` prüfen. Unter Windows die
Sicherheitseinstellungen der Datei oder `icacls` verwenden, um den Zugriff zu
beschränken. Geprüft werden nur lesbare Dateien mit erkanntem Header; unlesbare
Dateien können nicht als private Schlüssel erkannt werden und werden ausgelassen.

### `help` – Hilfe anzeigen

```sh
certKeys help
certKeys
```

Zeigt die verfügbaren Befehle und eine Kurzbeschreibung der Optionen.
`syncKeysToWindows` und `syncKeysFromWindows` erscheinen ausschließlich in
Unix-Shells unter Windows.

### `createKeys` – Schlüsselpaar erstellen

```sh
certKeys createKeys -context arbeit -keybits 4096
certKeys createKeys -default -keybits 4096
```

Erzeugt einen privaten RSA-Schlüssel sowie öffentliche Schlüssel im PEM- und
SSH-Format. Falls `~/.ssh` fehlt, wird es mit den Rechten `700` angelegt; der
private Schlüssel erhält die Rechte `600`. Der neu erzeugte private Schlüssel
wird ohne Passphrase gespeichert.

Existiert der ausgewählte private Schlüssel bereits, erscheint eine Rückfrage
zum Überschreiben. Enter bestätigt diese Rückfrage mit `Y`. Mit `-force` wird
sie übersprungen.

Fehlt der Standardschlüssel, kann anschließend das neue Schlüsselpaar zusätzlich
auf die Standarddateinamen kopiert werden. Auch hier ist die Vorgabe `Y`.

Parameter: `-context`, `-default`, `-algorithm`, `-keybits`, `-force`, `-trace`.

### `createPublicKeys` – Öffentliche Schlüssel erneut erzeugen

```sh
certKeys createPublicKeys -context arbeit
certKeys createPublicKeys -default
```

Leitet die Dateien `.pub` und `.pub.pem` erneut aus dem ausgewählten privaten
Schlüssel ab. Vorhandene öffentliche Dateien werden ersetzt; der private
Schlüssel bleibt unverändert. Das ist beispielsweise nach dem Verlust einer
öffentlichen Schlüsseldatei hilfreich.

Fehlt der private Schlüssel, wird stattdessen der Ablauf von `createKeys`
ausgeführt, einschließlich der dortigen Rückfragen.

Parameter: `-context`, `-default`, `-algorithm`, `-trace`; `-keybits` bei einer
notwendigen Neuerzeugung des privaten Schlüssels.

### `getPublicSSHKey` – Öffentlichen SSH-Schlüssel exportieren

```sh
certKeys getPublicSSHKey -context arbeit
certKeys getPublicSSHKey -context arbeit -target /tmp
certKeys getPublicSSHKey -default -target /tmp/mein-schluessel.pub
```

Kopiert ausschließlich die öffentliche `.pub`-Datei. Ohne `-target` wird sie ins
aktuelle Arbeitsverzeichnis kopiert. Ein vorhandenes Verzeichnis als Ziel erhält
eine Datei unter dem ursprünglichen Namen; ein Dateipfad kann den Export umbenennen.
Vorhandene Zieldateien können durch `cp` ersetzt werden.

Der private Schlüssel und der PEM-Export werden nicht mitkopiert. Fehlt die
öffentliche SSH-Datei, wird eine Meldung ausgegeben; der Befehl erzeugt sie nicht
selbst.

Parameter: `-context`, `-default`, `-algorithm`, `-target`, `-trace`.

### `makeKeyAsDefault` – Kontextschlüssel als Standard übernehmen

```sh
certKeys makeKeyAsDefault -context arbeit
```

Kopiert den ausgewählten privaten Schlüssel und beide öffentlichen Dateien auf
die Standarddateinamen, bei RSA also `id_rsa`, `id_rsa.pub` und `id_rsa.pub.pem`.
Alle drei Quelldateien müssen vorhanden sein.

Vorhandene Standarddateien werden ohne Rückfrage ersetzt; `-force` ist dafür
nicht nötig. Die Kontextdateien bleiben erhalten. Wird bereits `-default`
verwendet, ist keine Kopie notwendig und es erfolgt keine Änderung.

Parameter: `-context`, `-default`, `-algorithm`, `-trace`.

### `storeKeyAt` – Öffentlichen Schlüssel auf einen Server übertragen

```sh
certKeys storeKeyAt -context arbeit -target alice@server.example.com -alias arbeitsserver
```

Überträgt den ausgewählten öffentlichen SSH-Schlüssel mit `ssh-copy-id` an das
Ziel. Die Anmeldung kann eine Passwortabfrage oder andere SSH-Authentifizierung
erfordern. Der private Schlüssel bleibt lokal.

Fehlt die öffentliche SSH-Datei, fragt das Programm zunächst, ob sie erzeugt
werden soll; die Vorgabe ist `N`. Fehlt dabei auch der private Schlüssel, folgt
eine weitere Rückfrage zur Erzeugung.

Nach dem Übertragungsaufruf fragt das Programm, ob ein lokaler SSH-Eintrag angelegt
werden soll; die Vorgabe ist `Y`. Bei Bestätigung wird `createConfigEntry` mit
dem gewählten Ziel, Kontext und Alias verwendet. Danach kann die Verbindung
beispielsweise mit `ssh arbeitsserver` aufgebaut werden.

Parameter: `-target`, `-context`, `-default`, `-algorithm`, `-alias`, `-trace`;
`-keybits` bei einer notwendigen Neuerzeugung des privaten Schlüssels.

### `createConfigEntry` – SSH-Alias anlegen oder ersetzen

```sh
certKeys createConfigEntry -context arbeit -target alice@server.example.com -alias arbeitsserver
```

Schreibt einen Eintrag in `~/.ssh/config`, beispielsweise:

```sshconfig
Host arbeitsserver
     HostName      server.example.com
     IdentityFile  ~/.ssh/id@arbeit_rsa
     User          alice
```

Existiert derselbe Alias bereits, wird sein bisheriger Block ohne Rückfrage
entfernt und der neue Eintrag am Ende ergänzt. Andere Einträge bleiben erhalten.
Der Schlüssel muss beim Anlegen noch nicht existieren; dieser Befehl erzeugt und
überträgt keine Schlüssel.

Bei einem Ziel ohne `benutzer@`, etwa `server.example.com`, wird kein `User`-Wert
eingetragen. SSH ermittelt den Benutzer dann aus seinen übrigen Einstellungen
beziehungsweise dem lokalen Benutzernamen.

Parameter: `-target`, `-alias`, `-context`, `-default`, `-algorithm`, `-trace`.

### `removeConfigEntry` – SSH-Alias entfernen

```sh
certKeys removeConfigEntry -alias arbeitsserver
certKeys removeConfigEntry -target alice@server.example.com
```

Entfernt den zum Alias gehörenden `Host`-Block aus `~/.ssh/config`. Im zweiten
Beispiel wird der Alias `server` aus dem Ziel abgeleitet. Bei einem selbst
vergebenen Alias ist daher `-alias` anzugeben.

Schlüsseldateien und auf Servern hinterlegte öffentliche Schlüssel werden nicht
gelöscht. Eine Rückfrage erfolgt nicht. `-context` ist hier ohne Wirkung, weil
der Eintrag allein über seinen Alias ausgewählt wird.

Parameter: `-alias` oder `-target`, optional `-trace`.

### `showConfig` – SSH-Konfiguration anzeigen

```sh
certKeys showConfig
```

Gibt die gesamte Datei `~/.ssh/config` aus. Es gibt keine Auswahl nach Kontext
oder Alias. Fehlt die Datei, meldet `cat` dies als Fehler.

### `syncKeysToWindows` – Unix-Schlüssel nach Windows kopieren

Nur verfügbar unter WSL, MSYS/Git Bash und Cygwin. Unter macOS und nativem Linux
ist der Befehl ausgeblendet und ein direkter Aufruf wird abgewiesen.

Der Aufruf muss aus dem Windows-Benutzerverzeichnis erfolgen, das bereits ein
Unterverzeichnis `.ssh` enthält. Der folgende Beispielpfad zum Programm muss an
den eigenen Ablageort angepasst werden:

```sh
# Beispiel für WSL: Das Windows-Profil ist das Arbeitsverzeichnis.
cd /mnt/c/Users/MeinName
certKeys syncKeysToWindows
```

Kopiert alle regulären Dateien mit dem Namensanfang `id` aus `$HOME/.ssh` nach
`./.ssh`. Das umfasst private und öffentliche Schlüssel aller Kontexte, ebenso
Standarddateien. Vorhandene gleichnamige Zieldateien werden ohne Rückfrage ersetzt.

Die `Host`-Einträge aus der Unix-Konfiguration werden in `./.ssh/config`
übernommen. Zielblöcke mit passenden Aliasen werden ersetzt; zusätzliche Einträge
im Ziel bleiben erhalten. Es handelt sich um einen Abgleich der Host-Einträge,
keine vollständige Kopie sämtlicher globaler SSH-Einstellungen.

`-context`, `-default` und `-target` wählen hier keine Teilmenge oder andere
Verzeichnisse aus. Die Windows-Zielseite ist immer `.ssh` im Arbeitsverzeichnis.
Windows-Dateiberechtigungen werden durch diesen Befehl nicht eingerichtet.

### `syncKeysFromWindows` – Windows-Schlüssel nach Unix kopieren

Ebenfalls nur in Unix-Shells unter Windows verfügbar. Arbeitsverzeichnis und
Aufruf entsprechen dem vorherigen Befehl:

```sh
cd /mnt/c/Users/MeinName
certKeys syncKeysFromWindows
```

Kopiert alle regulären Dateien mit dem Namensanfang `id` aus `./.ssh` nach
`$HOME/.ssh`. Fehlende lokale Schlüsselverzeichnisse werden angelegt.
Schlüsseldateien erhalten die Rechte `600`; Dateien mit `pub` im Namen erhalten
anschließend `644`.

Die Host-Einträge aus `./.ssh/config` werden in die lokale Konfiguration
übernommen. Passende lokale Aliasblöcke und gleichnamige Schlüsseldateien werden
ohne Rückfrage ersetzt. Zusätzliche lokale Dateien und Host-Einträge werden
nicht gelöscht.

Auch hier wirken `-context`, `-default` und `-target` nicht als Filter oder
Pfadauswahl. In MSYS/Git Bash und Cygwin ist statt des WSL-Pfades der dort gültige
Pfad zum Windows-Profil zu verwenden. `$HOME/.ssh` und `./.ssh` müssen verschiedene
Verzeichnisse sein; insbesondere bei Git Bash kann `$HOME` bereits das
Windows-Profil sein, sodass kein getrennter Bestand zum Abgleichen existiert.

## Prüfungen und Entwicklung

Die Kompatibilitätstests benötigen zusätzlich Python 3:

```sh
python3 tests/test_compatibility.py
```

Sie verwenden ein temporäres Benutzerverzeichnis, ändern keine persönlichen
SSH-Schlüssel und kontaktieren keinen Server. Geprüft werden unter anderem
Schlüsselerzeugung, Kontextauswahl, Standardkopien, Export, SSH-Konfiguration und
Synchronisierung. Die Erkennung verschiedener Betriebssysteme wird dabei simuliert.

Der GitHub-Actions-Workflow ist für Debian 12/13, Ubuntu 22.04/24.04 und macOS
konfiguriert. Die Linux-Container prüfen zusätzlich die Ausführung mit den
jeweiligen Linux-Systemwerkzeugen.

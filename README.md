# guepardo-fresh-os-config

Configuração automatizada de ambiente de desenvolvimento para Ubuntu, Fedora/Nobara e Windows — terminal, dev stack, desktop apps e ajustes do sistema/GNOME.

## Instalação

### Linux (Ubuntu / Fedora / Nobara)
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dougkusanagi/guepardo-fresh-os-config/stable/install.sh)
```

### Windows (PowerShell)
Abra o PowerShell como Administrador e execute:
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; iex (irm 'https://raw.githubusercontent.com/dougkusanagi/guepardo-fresh-os-config/stable/install.ps1')
```

> O branch `stable` é usado no one-liner. A `master` pode conter mudanças em teste.

## Opções

```
Usage:
  ./install.sh [--distro=auto|ubuntu|fedora|nobara] [--mode=full|basic] [--theme=NAME] [--list-themes] [--help]

Options:
  --distro=NAME      Select installer family. Default: auto.
  --mode=MODE        Installation scope: full (dev + desktop + jogos) or basic (dev only). Default: full.
  --dry-run          Show what would be installed without making any changes.
  --theme=NAME       Apply one of the Omakub-inspired themes after desktop installation.
  --list-themes      List supported themes and exit.
  --help             Show this help.
```

Quando executado sem `--mode` em um terminal interativo, o script pergunta se você quer **Full** ou **Basic** (ou **Games**).

## Segurança

Os scripts fazem alterações no sistema. Recomendo inspecioná-los antes de executar:

### Linux
```bash
curl -fsSL https://raw.githubusercontent.com/dougkusanagi/guepardo-fresh-os-config/stable/install.sh | less
```

### Windows (PowerShell)
```powershell
(irm 'https://raw.githubusercontent.com/dougkusanagi/guepardo-fresh-os-config/stable/install.ps1')
```

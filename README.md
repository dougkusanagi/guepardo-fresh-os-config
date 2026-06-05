# new-linux-fresh-config

Configuração automatizada de ambiente de desenvolvimento para Ubuntu e Fedora/Nobara — terminal, dev stack, desktop apps e ajustes GNOME.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dougkusanagi/new-linux-fresh-config/stable/install.sh)
```

> O branch `stable` é usado no one-liner. A `master` pode conter mudanças em teste.

## Opções

```
Usage:
  ./install.sh [--distro=auto|ubuntu|fedora|nobara] [--theme=NAME] [--list-themes] [--help]

Options:
  --distro=NAME      Select installer family. Default: auto.
  --dry-run          Show what would be installed without making any changes.
  --theme=NAME       Apply one of the Omakub-inspired themes after desktop installation.
  --list-themes      List supported themes and exit.
  --help             Show this help.
```

## Segurança

O script faz alterações no sistema com `sudo`. Recomendo inspecioná-lo antes:

```bash
curl -fsSL https://raw.githubusercontent.com/dougkusanagi/new-linux-fresh-config/stable/install.sh | less
```

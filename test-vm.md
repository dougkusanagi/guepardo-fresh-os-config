# Teste Em VM

## Resumo

Este projeto suporta dois fluxos de instalacao:

1. Ubuntu, via `./install.sh` ou `./install.sh --distro=ubuntu`.
2. Fedora/Nobara, via `./install.sh --distro=fedora`, `./install.sh --distro=nobara`, ou `./install-fedora.sh`.

O `./install.sh` detecta a distro por `/etc/os-release` e escolhe o conjunto correto de scripts. O `./install-fedora.sh` continua existindo como atalho direto para Fedora/Nobara.

## Teste Automatizado

O script [`test.sh`](/home/silver/dev/guepardo-fresh-os-config/test.sh) aceita `--distro=ubuntu|fedora|nobara`.

Por padrao, `./test.sh` detecta a distro do host, usa container e nao executa a instalacao completa:

```bash
./test.sh
```

Executar tambem o instalador dentro do container:

```bash
./test.sh --run-installer
```

Ubuntu em VM limpa via Multipass:

```bash
./test.sh --distro=ubuntu --mode=multipass
```

Fedora em container:

```bash
./test.sh --distro=fedora --mode=container
```

Nobara em container aproximado:

```bash
./test.sh --distro=nobara --mode=container
```

O modo Nobara usa uma imagem Fedora por aproximacao. Ele valida o caminho CLI dos scripts Fedora/Nobara, mas nao substitui uma VM Nobara Desktop.

Validar sintaxe e lista de temas sem executar a instalacao:

```bash
./test.sh --distro=ubuntu --mode=static
./test.sh --distro=fedora --mode=static
./test.sh --distro=nobara --mode=static
```

Validar o bootstrap de container sem executar a instalacao, equivalente ao default:

```bash
./test.sh --distro=ubuntu --mode=container --syntax-only
./test.sh --distro=fedora --mode=container --syntax-only
./test.sh --distro=nobara --mode=container --syntax-only
```

Escolher release e tamanho da VM Ubuntu:

```bash
./test.sh --distro=ubuntu --mode=multipass --release=24.04 --cpus=2 --memory=4G --disk=30G
```

Manter a VM depois do teste:

```bash
./test.sh --distro=ubuntu --mode=multipass --keep-vm
```

## Limites Dos Testes Automatizados

O modo Multipass cobre apenas Ubuntu porque Multipass trabalha com imagens Ubuntu. Ele valida:

- Ubuntu limpo
- `sudo`
- `apt`
- instalacao das ferramentas CLI
- fluxo real do `install.sh` fora de container

O modo container valida:

- sintaxe dos scripts da distro selecionada
- `--list-themes`
- bootstrap minimo de pacotes
- caminho CLI do instalador

Ele nao valida:

- GNOME
- `gsettings`
- atalho do `flameshot`
- integracao visual de fontes
- temas do Omakub aplicados no GNOME
- Nautilus/Samba no desktop
- reboot pos-instalacao

## Teste Completo Em Ubuntu Desktop

Use `virt-manager` ou `GNOME Boxes` com `Ubuntu 24.04 Desktop`.

Configuracao sugerida:

- `2 vCPU`
- `4 GB RAM` no minimo
- `30 GB` de disco
- snapshot logo apos a instalacao limpa

Procedimento:

1. Crie uma VM com `Ubuntu 24.04 Desktop`.
2. Faca login e rode atualizacao basica do sistema.
3. Tire um snapshot chamado `clean-install`.
4. Clone este repositorio na VM.
5. Rode:

```bash
chmod +x install.sh
./install.sh --distro=ubuntu --theme=tokyo-night
```

6. Reinicie a VM.
7. Valide o checklist Ubuntu.

## Checklist Ubuntu

- `gh`, `eza`, `batcat`, `fdfind`, `btm`, `bun`, `uv`, `composer`, `podman` instalados
- alias `ls="eza"` presente no `~/.bashrc`
- alias `bat="batcat"` presente no `~/.bashrc`
- alias `fd="fdfind"` presente no `~/.bashrc`
- aliases `copy` e `paste` presentes
- `flatpak` funcionando
- apps desktop instalados
- `flameshot` associado a tecla `Print`
- fontes copiadas para `~/.local/share/fonts/guepardo-fresh-os-config`
- `fc-cache` executado sem erro
- `samba`, `smbclient` e `nautilus-share` instalados
- usuario no grupo `sambashare`
- compartilhamento aparece no Nautilus
- tema aplicado no GNOME
- wallpaper alterado

## Teste Completo Em Nobara Desktop

Use uma VM Nobara Desktop real. Para Nobara, o teste em container Fedora e apenas uma regressao rapida do caminho CLI.

Configuracao sugerida:

- `2 vCPU`
- `6 GB RAM` no minimo
- `40 GB` de disco
- snapshot logo apos a instalacao limpa

Procedimento:

1. Crie uma VM com Nobara Desktop.
2. Faca login e rode atualizacao basica do sistema.
3. Tire um snapshot chamado `clean-install`.
4. Clone este repositorio na VM.
5. Rode:

```bash
chmod +x install.sh install-fedora.sh
./install.sh --distro=nobara --theme=tokyo-night
```

6. Reinicie a VM.
7. Valide o checklist Nobara.

## Checklist Nobara/Fedora

- `gh`, `eza`, `bat`, `fd`, `btm`, `bun`, `uv`, `composer`, `podman` instalados
- alias `ls="eza"` presente no `~/.bashrc`
- alias `bottom="btm"` presente no `~/.bashrc`
- aliases `copy` e `paste` presentes
- `flatpak` funcionando com Flathub em modo system
- apps desktop instalados
- `flameshot` associado a tecla `Print`
- fontes copiadas para `~/.local/share/fonts/guepardo-fresh-os-config`
- `fc-cache` executado sem erro
- `samba` e `samba-client` instalados
- servico `smb` reinicia sem erro
- usuario no grupo `sambashare`
- `/var/lib/samba/usershares` existe com grupo `sambashare` e permissao `1770`
- compartilhamento de arquivos validado no desktop
- tema aplicado no GNOME
- wallpaper alterado

## Estrategia Recomendada

Use os testes em camadas:

- `./test.sh --distro=ubuntu --mode=multipass` para regressao Ubuntu em VM limpa
- `./test.sh --distro=fedora --mode=container` para regressao rapida Fedora/Nobara
- VM Ubuntu Desktop para validar integracao grafica Ubuntu
- VM Nobara Desktop para validar integracao grafica Nobara

## Troubleshooting

### Multipass cai logo ao iniciar

Se o host estiver com `/etc/resolv.conf` apontando para `Valet Linux`, o `multipassd` pode falhar ao subir o `dnsmasq`.

Sinal tipico:

- `failed to open file ... multipass_root_cert.pem`
- `snap services multipass` alternando entre `active` e `inactive`
- `journalctl -u snap.multipass.multipassd` mostrando erro do `dnsmasq`

No host afetado, verifique:

```bash
ls -l /etc/resolv.conf
```

Se ele apontar para algo como `/opt/valet-linux/resolv.conf`, troque temporariamente para um arquivo regular e rode o teste de novo:

```bash
sudo rm -f /etc/resolv.conf
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' | sudo tee /etc/resolv.conf >/dev/null
sudo snap restart multipass.multipassd
./test.sh --distro=ubuntu --mode=multipass
```

Depois do teste, restaure o setup do Valet se voce ainda precisar dele.

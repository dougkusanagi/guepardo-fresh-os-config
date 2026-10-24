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


## Regressão de extensões e dois monitores

Em Ubuntu e Fedora GNOME, conecte dois monitores no modo estendido. Execute `./install.sh --profiles=desktop --yes` como usuário normal. Confirme que não há pedidos interativos do site de extensões. Encerre a sessão (Wayland) e entre novamente.

- Dash to Dock aparece nos dois monitores e permanece após mais um logout/login.
- Multi Monitor Bar mostra relógio, calendário e controles do sistema no secundário; abra o menu de energia nesse monitor. Verifique os indicadores de tray instalados.
- Desconecte e reconecte o monitor secundário; as barras retornam.
- AI Quota Pulse aparece e abre preferências; a autenticação de contas é feita pelo usuário.
- Chrome, ChatGPT, Claude, T3 Code e Sloth Note abrem pelos atalhos. No Fedora, Claude e ChatGPT são apps web; no Ubuntu, Claude usa pacote oficial.
- Em uma instalação sem Go e sem release correspondente, rode `./install.sh` e confirme a mesma TUI. Cancele sem iniciar a instalação.
- Simule falha no download da Dash to Dock em uma sessão com Ubuntu Dock funcional: a dock anterior deve continuar habilitada e o erro deve ser reportado.

No Windows descartável, valide `-Profiles dev,desktop` incluindo a compilação do Sloth Note sem release, os links de regras dotagents via MSYS2 e o atalho do Sloth Note. Confira que falhas de dependências aparecem no resumo e causam saída 1. Estes cenários gráficos não são cobertos pelos mocks de CI.


### Apps adicionados na release v0.2.0

- Sem Go no PATH, execute o comando do README fixado em v0.2.0: confirme download do executável da mesma tag, SHA256 válido e abertura da TUI, sem compilação local.
- No Flameshot, faça uma captura e cancele outra; confirme ausência de notificações, mantendo o tray e o atalho Print.
- Confira ZapFast instalado e Whatsie removido, com dados do Whatsie preservados.
- Abra OneDriveGUI, autentique uma conta e escolha as pastas. Habilite auto-sync no perfil, encerre a sessão e entre novamente: a GUI deve abrir e sincronizar. No Windows, valide o OneDrive oficial no login.
- Sem Rust instalado, compile Sloth Note: confirme que Cargo/rustc ficam disponíveis antes do build e que falhas no bootstrap interrompem a compilação.
- Em dev+desktop, confira no log que dotagents roda uma única vez após Claude/ChatGPT, executando install.sh e bin/sync. Em dev sem desktop, deve sincronizar após as CLIs.
- Abra novo terminal e execute `vp --version` no Linux e Windows.

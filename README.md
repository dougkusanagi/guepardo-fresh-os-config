# guepardo-fresh-os-config

Instalador de ambiente para Ubuntu, Fedora/Nobara e Windows. No Linux, o orquestrador é escrito em Go e executa módulos por perfil. Os scripts Bash existentes continuam responsáveis pelas operações específicas de cada distribuição.

O branch `master` é a versão de produção; `dev` fica para desenvolvimento.

## Ubuntu ou WSL Ubuntu novo: um comando

Abra um terminal como seu usuário normal e cole o comando abaixo. Ele abre a TUI Go para escolher os perfis; detecta automaticamente Linux ou WSL. A senha de administrador é solicitada pelo `sudo`. A rede só muda se você selecionar o perfil `network`.

```bash
bash -c 'set -e; sudo apt-get update; sudo apt-get install -y curl ca-certificates python3; installer=$(mktemp); trap "rm -f -- \"$installer\"" EXIT; curl -fsSL --retry 3 --connect-timeout 20 --max-time 120 https://raw.githubusercontent.com/dougkusanagi/guepardo-fresh-os-config/v0.2.2/install.sh -o "$installer"; GUEPARDO_REF=v0.2.2 bash "$installer"'
```

O comando usa a release `v0.2.2`, com fontes e executável correspondentes. O instalador prefere o binário publicado, verifica SHA256 e a impressão das fontes antes de executá-lo. Se não houver binário compatível, usa Go local ou baixa uma toolchain Go temporária verificada por SHA256; esse comportamento vale também para execução com argumentos. Não instala Go no sistema. `GUEPARDO_BASH_FALLBACK=1` permite usar explicitamente o menu Bash.

Para instalação sem o menu, acrescente `--profiles=cli,dev,web --yes` à chamada final `bash "$installer"`. `--mode=full --yes` seleciona também desktop e jogos; no WSL use `--mode=wsl --yes`. Não execute o instalador inteiro com `sudo`.

Se a instalação parar, consulte o erro e o log e repita o mesmo comando depois de resolver a causa. O instalador reaproveita os apps que detecta como instalados e refaz etapas incompletas. Abra um novo terminal ao terminar; reinicie quando a instalação do desktop solicitar.

## Perfis

| Perfil | Instala | Requer interface gráfica |
| --- | --- | --- |
| `cli` | Git, gh, ripgrep, fzf, eza, dust, lazygit, yazi e utilitários | Não |
| `dev` | Node 24 LTS, npm, Bun, uv, Vite+ (vp), Podman, Codex CLI, Claude Code CLI e dotagents | Não |
| `web` | PHP, Composer e MySQL/MariaDB | Não |
| `desktop` | Chrome, Brave, OBS, VLC, ChatGPT, Claude, T3 Code, Sloth Note, OneDrive com GUI/autostart, ZapFast, editores, Flatpak e ajustes GNOME | Sim |
| `games` | Steam, Lutris, Heroic, Discord, gamescope e ferramentas de jogos; no Ubuntu, Vulkan/Mesa e driver NVIDIA recomendado quando há GPU NVIDIA; no Windows, Playnite e MSI Afterburner | Sim |
| `fonts` | Fontes do seu repositório privado de fontes | Não |
| `network` | IPv4 estático via NetworkManager | Não; use com cuidado em acesso remoto |

No Windows existem ainda os perfis `jellyfin` (servidor, tema GlassFin e plugins) e `wsl2` (WSL 2 + Ubuntu).

Os perfis são independentes. `games` não instala a stack web; `cli` não instala aplicativos gráficos, banco de dados nem altera a rede. A configuração de rede é sempre opcional.

## Fontes privadas

As fontes não ficam neste repositório público (várias são de uso pessoal/comercial). Elas ficam num repositório **privado**, por padrão `dougkusanagi/guepardo-fonts` (altere com `GUEPARDO_FONTS_REPO`). Para publicar a pasta local `fonts/` nele, depois de `gh auth login`:

```bash
./scripts/publish-fonts-private.sh
```

O perfil `fonts` usa, nesta ordem: `GUEPARDO_FONTS_DIR`, uma pasta `fonts/` no checkout, ou clona o repositório privado (exige `gh auth login` ou credenciais git). Sem acesso, o perfil falha com uma mensagem clara. Observação: o histórico antigo do git deste repositório ainda contém as fontes; para removê-las de vez é preciso reescrever o histórico.

## Linux

No checkout local (Go 1.22 ou superior é opcional):

```bash
./install.sh --profiles=cli --plan
./install.sh --profiles=cli,dev,web --doctor
./install.sh --profiles=cli --yes
./install.sh --profiles=cli,dev,web --yes
./install.sh --profiles=desktop,games --yes
./install.sh --profiles=network --network-interface=enp1s0 --network-address=192.168.1.77/24 --network-gateway=192.168.1.1 --plan
```

Sem argumentos, um terminal interativo abre o menu de módulos para o ambiente detectado. No Linux nativo, mostra somente Linux e os sete perfis, inicialmente desmarcados; dentro do WSL, mostra somente WSL com `cli,dev,web`, inicialmente selecionados. Não há abas ou atalhos para trocar de ambiente: o instalador configura a distribuição em execução. Use ↑/↓ e Espaço ou os números `1` a `8` no Linux e `1` a `4` no WSL para selecionar; Enter continua e Q cancela. O menu adapta o espaçamento à altura do terminal e respeita `NO_COLOR`. Todos inclui os sete perfis no Linux (inclusive rede) e apenas CLI/dev/web no WSL.

Ao selecionar rede, o instalador aplica a configuração pessoal fixa: **192.168.1.77/24**, gateway **192.168.1.1** e DNS **1.1.1.1**, sem perguntar os dados da rede. Detecta automaticamente uma conexão ativa do NetworkManager, priorizando cabo quando cabo e Wi-Fi estão ativos. Quem não quiser essa configuração deve desmarcar o perfil de rede. VPNs, bridges de containers e interfaces desconectadas são ignoradas. O backend modifica o perfil ativo por UUID, preservando tipo e credenciais Wi-Fi, sem desabilitar as outras redes nem alterar IPv6. Se a conexão mudar antes da aplicação, a instalação da rede é interrompida. Os argumentos `--network-*` continuam disponíveis para configuração explícita.

Para automação, use `--profiles` e `--yes` com os argumentos `--network-*`; `--profiles=all` seleciona os sete perfis. `--mode=wsl` continua disponível explicitamente, sem trocar o ambiente real. `--plan` detalha as ações sem mudanças; `--dry-run` simula sem sudo. `--jobs=N` limita downloads diretos concorrentes; APT, DNF e Flatpak continuam em sequência. O padrão é `--jobs=4`.

Atalhos legados: `--mode=full`, `basic`, `games` e `wsl`. `full` equivale a `cli,dev,web,desktop,games,fonts`; `basic` e `wsl` equivalem a `cli,dev,web`. Consulte `--list-profiles` e `--list-themes`.

`--doctor` verifica ferramentas locais, arquivos do instalador, arquitetura e permissões do diretório pessoal, sem instalar pacotes nem pedir senha. Sem perfis explícitos, verifica `cli`. Essa verificação também acontece automaticamente antes de uma instalação real; ela não certifica disponibilidade de todos os servidores de download. Os perfis `desktop` e `games` incluem apps exclusivos de x86_64; a verificação recusa esses grupos em ARM64 antes de alterar o sistema.

Cada perfil prepara suas próprias dependências e atualiza o índice de pacotes quando necessário. O APT aguarda até 120 segundos pelo lock de outra instalação e tenta novamente downloads transitórios. Downloads diretos têm tentativas e timeout, e só substituem arquivos anteriores após a transferência completa. Scripts remotos são baixados antes de executar; Composer e Node são verificados por checksum.

O perfil `dev` mantém Node 22/24 existente quando npm está disponível; caso contrário instala Node 24 LTS para o usuário. Os pacotes npm globais ficam em `~/.local`, e `~/.local/bin` e `~/.bun/bin` são adicionados ao PATH do Bash. O instalador configura atalhos no Bash; usuários de outros shells devem incluir esses diretórios no próprio PATH.

### Apps de IA e múltiplos monitores

`dev` instala Codex CLI, Claude Code CLI, Vite+ global (`vp`) e dotagents nos dois sistemas. Com `desktop` selecionado, dotagents é instalado apenas no fim do desktop, depois de Claude e ChatGPT, e executa `bin/sync` explicitamente. Em `dev` sem desktop, roda depois das CLIs, sem puxar apps gráficos. O checkout do dotagents fica separado dos diretórios de regras e memórias existentes; o instalador upstream preserva regras anteriores com backups. No Windows, instala MSYS2 e util-linux para executar o sincronizador Bash com locks e links reais; links exigem modo de desenvolvedor ou terminal elevado.

`desktop` inclui Chrome, ChatGPT, Claude Desktop, T3 Code e Sloth Note. No Linux, ChatGPT é um atalho de aplicativo web no Chrome. Claude Desktop usa o repositório APT oficial no Ubuntu; Fedora/Nobara recebem o aplicativo web Claude, pois não há pacote oficial RPM. T3 Code usa AppImage no Linux e Winget no Windows. O Sloth Note usa a release pública quando disponível; sem artefato, compila o código-fonte e instala o executável e um atalho. Essa compilação instala e verifica Cargo/rustc antes do build, além de Bun, Node e dependências Tauri (MSVC no Windows) e pode demorar. Erros são reportados; não são tratados como instalação concluída.

O perfil `desktop` troca o Whatsie pelo ZapFast, removendo o Flatpak antigo apenas depois de instalar o substituto e preservando seus dados. Instala OneDriveGUI + cliente OneDrive no Linux e OneDrive oficial no Windows, com inicialização automática. No Ubuntu, o cliente usa o repositório OBS recomendado pelo upstream para a versão detectada; Fedora/Nobara usam DNF. OneDriveGUI requer cliente >= 2.5.11. Abra a GUI para autenticar, escolher pastas e ativar auto-sync nos perfis desejados; o instalador não inicia sincronização de uma conta sem configuração. Desativa também as notificações de captura/cancelamento do Flameshot no arquivo de preferências e as notificações do aplicativo no GNOME.

No GNOME, `desktop` instala AI Quota Pulse e Multi Monitor Bar compatíveis com a versão do Shell. Configura Dash to Dock com `multi-monitor=true` e a barra superior nos monitores secundários, com relógio, calendário, indicadores e controles do sistema. As extensões ficam gravadas no disco e habilitadas nas preferências persistentes, inclusive para o primeiro login Wayland após a instalação. A dock anterior só é desativada depois que a substituta é instalada. Se não houver versão compatível da extensão, a instalação informa o erro.

Encerre a sessão e entre novamente após instalar extensões novas. Extensões de tray de terceiros podem ter limitações próprias de espelhamento. AI Quota Pulse e as barras GNOME não se aplicam ao Windows nem ao WSL sem desktop GNOME. A validação visual de logout/login e dois monitores deve ser feita em uma sessão GNOME real, conforme `test-vm.md`.

### Autenticação

O programa chama `sudo -v` uma vez antes da primeira etapa privilegiada. Enquanto instala, renova a credencial a cada 25 segundos; os módulos usam `sudo -n` para evitar uma nova pergunta de senha no meio do processo. Se a credencial não puder ser renovada, a instalação para com um erro claro. Em automação sem terminal, use `sudo` sem senha ou configure `SUDO_ASKPASS`.

### Servidor sem Go instalado

A release `v0.2.2` fornece `guepardo-linux-amd64`, `guepardo-linux-arm64`, `SOURCE_SHA256` e `SHA256SUMS`. O `install.sh` prefere esses executáveis mesmo quando Go já está instalado, verifica checksums e só usa o binário se a impressão das fontes corresponder ao checkout baixado. Sem correspondência, usa Go local ou prepara Go temporário; o executor Bash fica disponível apenas com `GUEPARDO_BASH_FALLBACK=1` quando não houver Go local/release correspondente. Um checksum incorreto encerra o processo sem executar o binário. O workflow continua gerando releases de cada atualização em `master`; fixe `GUEPARDO_REF` na tag ou commit que quiser executar.

```bash
GUEPARDO_REF=v0.2.2 bash <(curl -fsSL https://raw.githubusercontent.com/dougkusanagi/guepardo-fresh-os-config/v0.2.2/install.sh) --profiles=cli --yes
```

Você também pode fornecer um binário já compilado com `GUEPARDO_BIN=/caminho/guepardo ./install.sh --profiles=cli`.

## Windows

Para executar a mesma release no Windows:

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/dougkusanagi/guepardo-fresh-os-config/v0.2.2/install.ps1')))
```

O instalador PowerShell aceita os mesmos grupos principais:

```powershell
.\install.ps1 -Profiles 'cli,dev,web' -Plan
.\install.ps1 -Profiles 'games'
.\install.ps1 -Mode full -DryRun
```

`-Plan` e `-DryRun` listam os pacotes sem chamar o Winget. Os atalhos `-Mode full`, `basic`, `games`, `server`, `desktop` e `wsl` permanecem disponíveis. O Windows continua usando PowerShell e Winget; o executável Go implementa o fluxo Linux.

O Winget usa a fonte `winget`, modo silencioso e reaproveita aplicativos existentes. Se um app falhar, o instalador continua os demais, lista as falhas e sai com código `1`. Pedidos de reinicialização são informados no final. O Windows ainda pode exibir a confirmação de administrador (UAC) de alguns instaladores.

### Jellyfin e WSL 2 (Windows)

```powershell
.\install.ps1 -Profiles 'jellyfin' -Plan
.\install.ps1 -Profiles 'wsl2'
.\install.ps1 -Mode wsl   # cli,dev,web + WSL 2
```

`jellyfin` instala o servidor pelo Winget e aplica `jellyfin/polish.css` e os plugins com `modules/jellyfin.ps1 -SkipInstall`, preservando um backup do CSS anterior em `%LOCALAPPDATA%\WindowsFreshInstall\Jellyfin`; use `modules/jellyfin.ps1 -Restore` para voltar. Aguarde o assistente inicial do Jellyfin no navegador e tenha o login de administrador à mão. A configuração exige um checkout do repositório (não funciona pelo comando remoto de uma linha). `wsl2` pede UAC, habilita WSL e Virtual Machine Platform, instala o Ubuntu sem abrir o primeiro shell e define WSL 2; reinicie quando solicitado e execute `wsl -d Ubuntu` uma vez para criar o usuário. O perfil `dev` também configura Node.js LTS via NVM for Windows. Virtualização Intel VT-x/AMD-V precisa estar habilitada no firmware.

### Notas para bibliotecas de mídia

`templates/media-library/AGENTS.md` guarda as notas da biblioteca compartilhada entre Jellyfin e qBittorrent (seed, hardlinks, `.ignore`, escaneamento). Para copiá-las para uma biblioteca:

```bash
./install.sh --helpers
./install.sh --media-agents "/caminho/da/biblioteca"
```

Só `AGENTS.md` é copiado; um arquivo existente diferente é preservado.

## Desenvolvimento e testes

```bash
go test ./...
./test.sh --mode=static --distro=ubuntu
./test.sh --mode=static --distro=fedora
./scripts/build-release.sh
pwsh -NoProfile -File tests/test-windows.ps1
pwsh -NoProfile -File tests/windows-reliability.ps1
pwsh -NoProfile -File tests/jellyfin-suite.ps1
./test.sh --mode=container --distro=ubuntu --profiles=dev --run-installer
```

Logs dos executores Go e Bash ficam em `~/.local/state/guepardo/logs` (ou em `$XDG_STATE_HOME/guepardo/logs`). Nenhum teste local instala pacotes do sistema. Os testes incluem downloads interrompidos, checksums, autenticação, cancelamento, seleção de perfis e resultados do Winget simulado. O GitHub Actions executa as verificações Linux e Windows a cada push/PR. Para instalação real em ambiente descartável, use os modos de container/VM de `test.sh`.

Containers validam os perfis de terminal; GNOME, Wayland, compartilhamento Samba e integração de AppImages precisam da validação em VM com desktop descrita em [test-vm.md](test-vm.md). Fedora/Nobara têm os mesmos testes simulados, mas isso não substitui uma instalação real dessas distribuições. A disponibilidade de apps, PPAs e serviços externos pode mudar; uma falha identifica a etapa e preserva os logs para diagnóstico.

Em hosts com um perfil AppArmor para MySQL, a configuração do pacote pode falhar em containers Podman sem privilégios, com `kill: Permission denied` no `postinst`. Nesse caso, valide o perfil `web` em uma VM Ubuntu; desativar AppArmor globalmente não é necessário. Serviços também precisam de uma VM com systemd para validar sua inicialização automática.

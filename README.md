# guepardo-fresh-os-config

Instalador de ambiente para Ubuntu, Fedora/Nobara e Windows. No Linux, o orquestrador é escrito em Go e executa módulos por perfil. Os scripts Bash existentes continuam responsáveis pelas operações específicas de cada distribuição.

O branch `master` é a versão de produção; `dev` fica para desenvolvimento.

## Ubuntu ou WSL Ubuntu novo: um comando

Abra um terminal como seu usuário normal e cole o comando abaixo. Ele abre a TUI Go para escolher os perfis; detecta automaticamente Linux ou WSL. A senha de administrador é solicitada pelo `sudo`. A rede só muda se você selecionar o perfil `network`.

```bash
bash -c 'set -e; sudo apt-get update; sudo apt-get install -y curl ca-certificates python3; installer=$(mktemp); trap "rm -f -- \"$installer\"" EXIT; curl -fsSL --retry 3 --connect-timeout 20 --max-time 120 https://raw.githubusercontent.com/dougkusanagi/guepardo-fresh-os-config/master/install.sh -o "$installer"; bash "$installer"'
```

O comando usa `master`; mudanças em outra branch só chegam a ele após a integração. O fluxo de publicação gera binários Linux com checksums e identificação das fontes a cada push em `master`. Sem release compatível e sem Go instalado, o modo sem argumentos baixa uma toolchain Go temporária verificada por SHA256 para abrir a mesma TUI. Não instala Go no sistema. `GUEPARDO_BASH_FALLBACK=1` permite usar explicitamente o menu Bash.

Para instalação sem o menu, acrescente `--profiles=cli,dev,web --yes` à chamada final `bash "$installer"`. `--mode=full --yes` seleciona também desktop e jogos; no WSL use `--mode=wsl --yes`. Não execute o instalador inteiro com `sudo`.

Se a instalação parar, consulte o erro e o log e repita o mesmo comando depois de resolver a causa. O instalador reaproveita os apps que detecta como instalados e refaz etapas incompletas. Abra um novo terminal ao terminar; reinicie quando a instalação do desktop solicitar.

## Perfis

| Perfil | Instala | Requer interface gráfica |
| --- | --- | --- |
| `cli` | Git, gh, ripgrep, fzf, eza, dust, lazygit, yazi e utilitários | Não |
| `dev` | Node 24 LTS, npm, Bun, uv, Podman, Codex CLI, Claude Code CLI e dotagents | Não |
| `web` | PHP, Composer e MySQL/MariaDB | Não |
| `desktop` | Chrome, ChatGPT, Claude, T3 Code, Sloth Note, editores, Flatpak e ajustes GNOME | Sim |
| `games` | Steam, Lutris, Heroic, Discord e ferramentas de jogos | Sim |
| `fonts` | Fontes incluídas no repositório | Não |
| `network` | IPv4 estático via NetworkManager | Não; use com cuidado em acesso remoto |

Os perfis são independentes. `games` não instala a stack web; `cli` não instala aplicativos gráficos, banco de dados nem altera a rede. A configuração de rede é sempre opcional.

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

Sem argumentos, um terminal interativo abre o menu de módulos. Use **Tab** ou **W** para alternar entre **Linux** e **WSL**. Linux começa sem módulos marcados; WSL mostra apenas `cli,dev,web`, inicialmente selecionados, e permite desmarcar os módulos que não quiser. Desktop, jogos, fontes e rede aparecem apenas no menu Linux. Ao voltar para Linux, sua seleção anterior é recuperada. Dentro do WSL, esse ambiente é detectado automaticamente. Essa opção configura os apps na distribuição atual; execute dentro do Ubuntu no WSL para configurar esse ambiente. Use ↑/↓ e Espaço ou pressione os números `1` a `8` no Linux ou `1` a `4` no WSL para marcar várias opções; Enter continua e `Q` cancela. O menu Go destaca o módulo em foco e mostra sua descrição, adapta o espaçamento à altura do terminal e respeita `NO_COLOR`. A opção **Todos** marca os sete perfis no Linux, inclusive rede; no WSL, marca somente CLI, desenvolvimento e stack web. Ao marcar rede, o instalador solicita os dados IPv4 antes de alterar a conexão. Para automação, informe `--profiles` e `--yes`; `--profiles=all` equivale aos sete perfis. `--plan` detalha as ações previstas; `--dry-run` simula as etapas sem `sudo`. `--jobs=N` limita a concorrência de instaladores de download direto; `apt`, `dnf` e Flatpak são executados em sequência. O índice de pacotes é reutilizado entre perfis e atualizado novamente quando um repositório muda. O padrão é `--jobs=4`.

Atalhos legados: `--mode=full`, `basic`, `games` e `wsl`. `full` equivale a `cli,dev,web,desktop,games,fonts`; `basic` e `wsl` equivalem a `cli,dev,web`. Consulte `--list-profiles` e `--list-themes`.

`--doctor` verifica ferramentas locais, arquivos do instalador, arquitetura e permissões do diretório pessoal, sem instalar pacotes nem pedir senha. Sem perfis explícitos, verifica `cli`. Essa verificação também acontece automaticamente antes de uma instalação real; ela não certifica disponibilidade de todos os servidores de download. Os perfis `desktop` e `games` incluem apps exclusivos de x86_64; a verificação recusa esses grupos em ARM64 antes de alterar o sistema.

Cada perfil prepara suas próprias dependências e atualiza o índice de pacotes quando necessário. O APT aguarda até 120 segundos pelo lock de outra instalação e tenta novamente downloads transitórios. Downloads diretos têm tentativas e timeout, e só substituem arquivos anteriores após a transferência completa. Scripts remotos são baixados antes de executar; Composer e Node são verificados por checksum.

O perfil `dev` mantém Node 22/24 existente quando npm está disponível; caso contrário instala Node 24 LTS para o usuário. Os pacotes npm globais ficam em `~/.local`, e `~/.local/bin` e `~/.bun/bin` são adicionados ao PATH do Bash. O instalador configura atalhos no Bash; usuários de outros shells devem incluir esses diretórios no próprio PATH.

### Apps de IA e múltiplos monitores

`dev` instala Codex CLI, Claude Code CLI e dotagents nos dois sistemas. O checkout do dotagents fica separado dos diretórios de regras e memórias existentes; o instalador upstream preserva regras anteriores com backups. No Windows, instala MSYS2 e util-linux para executar o sincronizador Bash com locks e links reais; links exigem modo de desenvolvedor ou terminal elevado.

`desktop` inclui Chrome, ChatGPT, Claude Desktop, T3 Code e Sloth Note. No Linux, ChatGPT é um atalho de aplicativo web no Chrome. Claude Desktop usa o repositório APT oficial no Ubuntu; Fedora/Nobara recebem o aplicativo web Claude, pois não há pacote oficial RPM. T3 Code usa AppImage no Linux e Winget no Windows. O Sloth Note usa a release pública quando disponível; sem artefato, compila o código-fonte e instala o executável e um atalho. Essa compilação instala Bun, Node, Rust e dependências Tauri (MSVC no Windows) e pode demorar. Erros são reportados; não são tratados como instalação concluída.

No GNOME, `desktop` instala AI Quota Pulse e Multi Monitor Bar compatíveis com a versão do Shell. Configura Dash to Dock com `multi-monitor=true` e a barra superior nos monitores secundários, com relógio, calendário, indicadores e controles do sistema. As extensões ficam gravadas no disco e habilitadas nas preferências persistentes, inclusive para o primeiro login Wayland após a instalação. A dock anterior só é desativada depois que a substituta é instalada. Se não houver versão compatível da extensão, a instalação informa o erro.

Encerre a sessão e entre novamente após instalar extensões novas. Extensões de tray de terceiros podem ter limitações próprias de espelhamento. AI Quota Pulse e as barras GNOME não se aplicam ao Windows nem ao WSL sem desktop GNOME. A validação visual de logout/login e dois monitores deve ser feita em uma sessão GNOME real, conforme `test-vm.md`.

### Autenticação

O programa chama `sudo -v` uma vez antes da primeira etapa privilegiada. Enquanto instala, renova a credencial a cada 25 segundos; os módulos usam `sudo -n` para evitar uma nova pergunta de senha no meio do processo. Se a credencial não puder ser renovada, a instalação para com um erro claro. Em automação sem terminal, use `sudo` sem senha ou configure `SUDO_ASKPASS`.

### Servidor sem Go instalado

Publique uma release com os quatro arquivos de `./scripts/build-release.sh`: `guepardo-linux-amd64`, `guepardo-linux-arm64`, `SOURCE_SHA256` e `SHA256SUMS`. O `install.sh` verifica os checksums e usa o binário somente se a impressão dos arquivos de origem corresponder ao checkout baixado. Sem Go 1.22 ou superior, procura uma release compatível e, se não encontrar, usa o executor Bash com os mesmos perfis, logs e renovação de `sudo`. Um checksum incorreto encerra o processo sem executar o binário. O comando remoto do branch `master` usa os arquivos desse branch; publique a release correspondente ao promover uma versão para `master`.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dougkusanagi/guepardo-fresh-os-config/master/install.sh) --profiles=cli --yes
```

Você também pode fornecer um binário já compilado com `GUEPARDO_BIN=/caminho/guepardo ./install.sh --profiles=cli`.

## Windows

O instalador PowerShell aceita os mesmos grupos principais:

```powershell
.\install.ps1 -Profiles 'cli,dev,web' -Plan
.\install.ps1 -Profiles 'games'
.\install.ps1 -Mode full -DryRun
```

`-Plan` e `-DryRun` listam os pacotes sem chamar o Winget. Os atalhos `-Mode full`, `basic`, `games`, `server`, `desktop` e `wsl` permanecem disponíveis. O Windows continua usando PowerShell e Winget; o executável Go implementa o fluxo Linux.

O Winget usa a fonte `winget`, modo silencioso e reaproveita aplicativos existentes. Se um app falhar, o instalador continua os demais, lista as falhas e sai com código `1`. Pedidos de reinicialização são informados no final. O Windows ainda pode exibir a confirmação de administrador (UAC) de alguns instaladores.

## Desenvolvimento e testes

```bash
go test ./...
./test.sh --mode=static --distro=ubuntu
./test.sh --mode=static --distro=fedora
./scripts/build-release.sh
pwsh -NoProfile -File tests/test-windows.ps1
pwsh -NoProfile -File tests/windows-reliability.ps1
./test.sh --mode=container --distro=ubuntu --profiles=dev --run-installer
```

Logs dos executores Go e Bash ficam em `~/.local/state/guepardo/logs` (ou em `$XDG_STATE_HOME/guepardo/logs`). Nenhum teste local instala pacotes do sistema. Os testes incluem downloads interrompidos, checksums, autenticação, cancelamento, seleção de perfis e resultados do Winget simulado. O GitHub Actions executa as verificações Linux e Windows a cada push/PR. Para instalação real em ambiente descartável, use os modos de container/VM de `test.sh`.

Containers validam os perfis de terminal; GNOME, Wayland, compartilhamento Samba e integração de AppImages precisam da validação em VM com desktop descrita em [test-vm.md](test-vm.md). Fedora/Nobara têm os mesmos testes simulados, mas isso não substitui uma instalação real dessas distribuições. A disponibilidade de apps, PPAs e serviços externos pode mudar; uma falha identifica a etapa e preserva os logs para diagnóstico.

Em hosts com um perfil AppArmor para MySQL, a configuração do pacote pode falhar em containers Podman sem privilégios, com `kill: Permission denied` no `postinst`. Nesse caso, valide o perfil `web` em uma VM Ubuntu; desativar AppArmor globalmente não é necessário. Serviços também precisam de uma VM com systemd para validar sua inicialização automática.

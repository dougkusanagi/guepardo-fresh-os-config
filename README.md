# guepardo-fresh-os-config

Instalador de ambiente para Ubuntu, Fedora/Nobara e Windows. No Linux, o orquestrador é escrito em Go e executa módulos por perfil. Os scripts Bash existentes continuam responsáveis pelas operações específicas de cada distribuição.

## Perfis

| Perfil | Instala | Requer interface gráfica |
| --- | --- | --- |
| `cli` | Git, gh, ripgrep, fzf, eza, dust, lazygit, yazi e utilitários | Não |
| `dev` | Node, npm, Bun, uv, Podman e ferramentas de desenvolvimento | Não |
| `web` | PHP, Composer e MySQL/MariaDB | Não |
| `desktop` | Navegadores, editores, Flatpak e ajustes GNOME | Sim |
| `games` | Steam, Lutris, Heroic, Discord e ferramentas de jogos | Sim |
| `fonts` | Fontes incluídas no repositório | Sim |
| `network` | IPv4 estático via NetworkManager | Não; use com cuidado em acesso remoto |

Os perfis são independentes. `games` não instala a stack web; `cli` não instala aplicativos gráficos, banco de dados nem altera a rede. A configuração de rede é sempre opcional.

## Linux

No checkout local (Go 1.22 ou superior):

```bash
./install.sh --profiles=cli --plan
./install.sh --profiles=cli --yes
./install.sh --profiles=cli,dev,web --yes
./install.sh --profiles=desktop,games --yes
./install.sh --profiles=network --network-interface=enp1s0 --network-address=192.168.1.77/24 --network-gateway=192.168.1.1 --plan
```

Sem argumentos, um terminal interativo mostra caixas de seleção para os perfis, inicialmente desmarcadas. Use ↑/↓ e Espaço ou pressione os números `1` a `8` para marcar várias opções; Enter continua e `Q` cancela. A opção **Todos** marca os sete perfis, inclusive rede. Ao marcar rede, o instalador solicita os dados IPv4 antes de alterar a conexão. Para automação, informe `--profiles` e `--yes`; `--profiles=all` equivale aos sete perfis. `--plan` detalha as ações previstas; `--dry-run` simula as etapas sem `sudo`. `--jobs=N` limita a concorrência de instaladores de download direto; `apt`, `dnf` e Flatpak são executados em sequência. O índice de pacotes é reutilizado entre perfis e atualizado novamente quando um repositório muda. O padrão é `--jobs=4`.

Atalhos legados: `--mode=full`, `basic`, `games` e `wsl`. `full` equivale a `cli,dev,web,desktop,games,fonts`; `basic` e `wsl` equivalem a `cli,dev,web`. Consulte `--list-profiles` e `--list-themes`.

### Autenticação

O programa chama `sudo -v` uma vez antes da primeira etapa privilegiada. Enquanto instala, renova a credencial a cada 25 segundos; os módulos usam `sudo -n` para evitar uma nova pergunta de senha no meio do processo. Se a credencial não puder ser renovada, a instalação para com um erro claro. Em automação sem terminal, use `sudo` sem senha ou configure `SUDO_ASKPASS`.

### Servidor sem Go instalado

Publique uma release com os arquivos de `./scripts/build-release.sh`: `guepardo-linux-amd64`, `guepardo-linux-arm64` e `SHA256SUMS`. O `install.sh` baixa o binário adequado e verifica o SHA-256. Se ainda não houver release, ele usa um executor Bash com os mesmos perfis e renovação de `sudo`. O comando remoto do branch `stable` usa os arquivos desse branch; publique a release correspondente ao promover uma versão para `stable`.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dougkusanagi/guepardo-fresh-os-config/stable/install.sh) --profiles=cli --yes
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

## Desenvolvimento e testes

```bash
go test ./...
./test.sh --mode=static --distro=ubuntu
./test.sh --mode=static --distro=fedora
./scripts/build-release.sh
```

Logs do instalador Go ficam em `~/.local/state/guepardo/logs` (ou em `$XDG_STATE_HOME/guepardo/logs`). Nenhum teste local instala pacotes do sistema. Para instalação real em ambiente descartável, use os modos de container/VM de `test.sh`.

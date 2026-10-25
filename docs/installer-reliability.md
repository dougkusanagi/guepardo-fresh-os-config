# Instalação, recuperação e desempenho

O catálogo `catalog/apps.json` é a fonte dos aplicativos Windows, dependências, alternativas Scoop e perfis/receitas Linux. Os detalhes dos pacotes APT/DNF e ajustes de cada distribuição continuam nas respectivas receitas Bash. O catálogo é incorporado ao executável Go e incluído na impressão de código da release.

## Windows

```powershell
.\install.cmd -Doctor
.\install.cmd -Profiles dev,desktop -Plan
.\install.cmd -Apps GitHub.cli,sharkdp.bat -Plan
.\install.cmd -Profiles dev,desktop -ExcludeApps Oracle.MySQL -Provider auto
.\install.cmd -Resume
.\install.cmd -RetryFailed
.\install.cmd -Profiles dev -BootstrapScoop
.\install.cmd -Profiles desktop -PrefetchOnly -Jobs 4
```

Sem argumentos, o menu permite marcar perfis ou expandi-los com `e N` para escolher aplicativos individuais. Dependências são incluídas automaticamente. `-ExcludeApps` não pode remover uma dependência necessária. `-Apps` e `-ExcludeApps` recebem os IDs do catálogo. O modo sem cores funciona com `-NoColor` ou `NO_COLOR`.

O antigo `winstall-dougkusanagi-basic.ps1` encaminha para o mesmo instalador e aceita os mesmos argumentos. Não mantém outra lista independente de pacotes.

`auto` usa Scoop para as ferramentas com mapeamento quando Scoop está disponível e mantém Winget para os demais pacotes. `-BootstrapScoop` instala Scoop e aria2 explicitamente, em terminal sem elevação. Instalações Winget existentes são detectadas antes de adotar Scoop, evitando duplicação. Não há troca automática para Chocolatey depois de uma instalação parcial.

O estado fica em `%LOCALAPPDATA%\Guepardo\State\install-state.json`. Cada etapa registra provedor, impressão da definição, resultado e horário. As gravações são atômicas, com backup do estado anterior. Uma trava impede duas execuções no mesmo diretório de estado.

As chamadas de instalação Winget/Scoop têm logs separados por aplicativo em `%LOCALAPPDATA%\Guepardo\Logs`. O registro da etapa inclui o código de saída e o caminho do diagnóstico. Os instaladores personalizados mantêm os detalhes no log geral.

`-Resume` verifica os resultados existentes. `-RetryFailed` seleciona etapas com falha, bloqueadas, interrompidas ou aguardando reinicialização, incluindo suas dependências. Etapas de configuração (sincronização dotagents, Jellyfin e WSL) executam novamente; ter um binário instalado não prova que sua configuração está correta. O estado não substitui verificação de pacote e comandos esperados. Um código de sucesso sem verificação válida é registrado como falha. Uma dependência com falha ou reinício pendente bloqueia seus dependentes.

Instalações permanecem sequenciais. `-Jobs 1..8` controla apenas os downloads diretos antecipados de Sloth Note, ZapFast e Composer quando aplicável. Não paraleliza MSI, Winget ou configurações. Winget e Scoop continuam controlando seus próprios downloads. A velocidade exibida é a média da transferência; reutilização de cache é identificada separadamente.

O cache fica em `%LOCALAPPDATA%\Guepardo\Cache`. Arquivos completos são verificados contra o SHA256 publicado, quando fornecido, e contra a impressão local registrada. Sem checksum upstream, a impressão local detecta corrupção, mas não autentica o publicador. URLs sem checksum são revalidadas após 24 horas e não retomam fragmentos de uma execução anterior. Downloads com SHA256 upstream podem retomar fragmentos; a validação final impede aceitar bytes incompletos ou misturados. Os scripts remotos Vite+ e Scoop não reutilizam cache antigo.

`-StateDirectory` e `-CacheDirectory` permitem usar pastas próprias. Estado corrompido causa erro explícito e é preservado para diagnóstico. `-InteractiveFallback` autoriza uma tentativa visível após falha silenciosa; ela não ocorre por padrão. Falhas transitórias de rede reconhecidas têm até três tentativas; erros de instalador não são repetidos automaticamente.

## Medir lentidão

No Windows, `-Resume` sem novos perfis ou apps recupera automaticamente a seleção anterior. Use `-Resume -Plan` para conferi-la sem instalar.

A seleção é salva antes do bootstrap e dos downloads. Etapas ainda não iniciadas ficam pendentes; uma interrupção não as remove da próxima tentativa com `-RetryFailed`.

```powershell
.\scripts\benchmark-downloads.ps1 -Uri 'https://servidor-oficial/caminho/instalador.exe'
```

O benchmark solicita apenas o primeiro MiB por padrão, limita tamanho/tempo e informa host, status HTTP e bytes por segundo. Alguns servidores não aceitam Range; nesse caso não oferece uma medida comparável. Não altera configurações do sistema. Para Winget, compare manualmente `network.downloader` como `do` e `wininet` em `winget settings`; uma troca não garante melhoria. aria2 também depende das capacidades e limites do servidor.

## Linux

```bash
./install.sh --profiles=dev --yes --resume
./install.sh --profiles=dev,desktop --yes --retry-failed
./install.sh --profiles=dev --yes --state-dir="$HOME/.local/state/guepardo/steps"
```

Os checkpoints por aplicativo ficam em `$XDG_STATE_HOME/guepardo/steps` ou `~/.local/state/guepardo/steps`. Etapas com verificador conhecido só são ignoradas após detectar a ferramenta novamente. Ajustes de configuração e etapas sem verificador são refeitos; os gerenciadores de pacotes mantêm sua própria detecção. O fallback Bash também aceita as opções de recuperação. `--retry-failed` no Linux reprocessa as receitas selecionadas, verificando e pulando os apps concluídos que têm verificador; não é uma transação de rollback.

O cache de downloads usa `$XDG_CACHE_HOME/guepardo/downloads` ou `~/.cache/guepardo/downloads`, configurável com `GUEPARDO_CACHE_DIR`. `GUEPARDO_CACHE_MAX_AGE=0` desabilita reutilização de conteúdo sem checksum. Downloads não substituem o destino antes de terminar, possuem detecção de conexão sem progresso e retomam transferências com checksum conhecido. Travas de download abandonadas por processos encerrados são recuperadas.

## Verificação e publicação

A publicação depende de ambas as suítes Windows e Linux por workflow reutilizável. As releases incluem binários Linux, arquivo ZIP com o checkout para Windows, SHA256SUMS e atestados de origem. O checksum verifica integridade; o atestado associa os artefatos ao build do GitHub Actions.

Os testes automáticos simulam gerenciadores e falhas, usam um servidor HTTP local para interrupções e concorrência, e validam dependências, cache, estado, seleção e Jellyfin. `Real installer smoke test (manual)` instala um conjunto pequeno de ferramentas em runners descartáveis Windows/Ubuntu. Isso não equivale a instalar todos os aplicativos nem valida GNOME, reboot, drivers ou login em contas: essas integrações exigem o roteiro de VM em `test-vm.md`.

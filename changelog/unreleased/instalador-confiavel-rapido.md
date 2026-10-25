# Catálogo, recuperação e downloads

- Move os apps Windows e metadados dos perfis para um catálogo compartilhado com o orquestrador Go.
- Adiciona seleção individual, diagnóstico, provedores Winget/Scoop, recuperação por etapa, verificações após instalar e propagação de falhas nas dependências.
- Adiciona cache validado, retomada de transferências com checksum conhecido, detecção de downloads parados e prefetch limitado de downloads diretos.
- Adiciona checkpoints Linux e trava de execução do orquestrador, mantendo os ajustes de configuração repetíveis.
- Faz a publicação depender dos testes de ambas as plataformas e inclui ZIP Windows e atestados de origem.
- Adiciona testes com servidor HTTP local, testes de integração isolados e workflow manual de smoke test real.

Consulte `docs/installer-reliability.md` para os comandos, limites e localização dos arquivos de estado.

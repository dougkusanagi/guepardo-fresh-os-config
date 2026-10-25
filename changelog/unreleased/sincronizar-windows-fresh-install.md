# Sincronização das duas pastas do instalador

- Disponibiliza também em `windows-fresh-install` os perfis Windows, os scripts Linux, as integrações com Sloth Note, dotagents e AI Quota Pulse, testes e workflows.
- Preserva o launcher independente do Jellyfin e sua documentação em `docs/windows-jellyfin.md`.
- Usa o launcher Windows local que executa `install.ps1`, corrigindo a versão que apagava o bootstrap antes de executá-lo.
- Inclui Rust no perfil `dev` no Windows, Ubuntu e Fedora, independentemente da compilação do Sloth Note.
- Mantém os binários antigos `guepardo.exe` e seu backup apenas como artefatos locais; o instalador Windows atual usa PowerShell.

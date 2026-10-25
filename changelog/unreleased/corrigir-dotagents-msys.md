# Corrigir aspas na instalação Windows do dotagents

- Substitui os comandos `bash -c` por um script Bash com modos separados para runtime, dependências e instalação/sync.
- Transmite caminhos por ambiente, preservando espaços, parênteses, apóstrofos e caracteres Unicode.
- Preserva o código de saída e interrompe sync quando install falha.
- Remove o diagnóstico genérico que atribuía qualquer falha a permissões de links simbólicos.
- Garante LF nos scripts Bash e testa a ponte nativa no PowerShell 7 e 5.1 com Git Bash e MSYS2 quando disponíveis, sem instalar pacotes nem modificar regras reais do usuário.

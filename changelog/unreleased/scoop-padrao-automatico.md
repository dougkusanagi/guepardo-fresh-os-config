# Scoop e aria2 por padrão

- O comando simples prepara Scoop e aria2 antes de instalar os apps, sem exigir parâmetros extras.
- Amplia os mapeamentos oficiais de CLI e desktop, preparando o bucket Extras quando necessário.
- Ativa aria2 com fallback do downloader e suporta o bootstrap oficial em terminal elevado.
- Preserva apps existentes, interrompe com erro se a preparação falhar e mantém o estado para retomar.
- Modos de consulta não instalam gerenciadores; `-Provider winget` mantém a escolha explícita de Winget.

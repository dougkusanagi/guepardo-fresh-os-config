# Preservar ambiente, temporários e resultados

- Atualiza PATH sem substituir TEMP/TMP ou variáveis da sessão por valores da máquina.
- Usa um diretório temporário próprio e gravável por execução, herdado pelos instaladores filhos, restaurando TEMP/TMP ao finalizar.
- Trata arquivos temporários bloqueados como aviso de limpeza, preservando o resultado do Composer e continuando os próximos apps.
- Corrige também o atalho refreshenv gerado e atualiza sua versão antiga sem remover conteúdo do usuário.
- Verifica comandos com sufixos Windows e permite reparo via Scoop quando um registro Winget não corresponde a uma CLI utilizável.
- Evita mensagens de app Scoop ausente durante a detecção e trata a ausência de release do Sloth Note como caminho normal de compilação.
- Adiciona regressões para ambiente herdado, limpeza bloqueada, registro quebrado, perfil antigo e instalação real de Vite+ em runner descartável.

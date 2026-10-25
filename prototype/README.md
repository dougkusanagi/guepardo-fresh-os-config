# Guepardo Desktop — protótipo de interface

Abra `index.html` no navegador. HTML, CSS e JavaScript sem build ou dependências locais. As fontes têm fallback para Segoe UI se estiver offline.

A biblioteca usa uma cópia do catálogo Windows real. Os estados são fictícios e ficam somente em memória. Verificação, diagnóstico e instalação são demonstrações: nenhum comando de instalação é executado. Recarregar a página restaura os dados.

Interface simplificada: uma lista de aplicativos, busca, categoria e filtros de estado. Informações técnicas, descrições e diagnósticos aparecem apenas ao abrir os detalhes. A ação de instalar aparece quando há uma seleção. Itens que aguardam reinicialização não podem ser selecionados para reinstalação.

O checkbox “Selecionar todos desta lista” atua nos resultados filtrados e fica parcialmente marcado quando só parte deles está selecionada. “Selecionar todos do catálogo” permite incluir os demais resultados sem limpar filtros. Apenas aplicativos ausentes ou com falha são elegíveis. Desmarcar a lista preserva seleções fora do filtro, cuja quantidade aparece na barra inferior. “Selecionar falhas” substitui a seleção pelas falhas do catálogo. A quantidade no botão de instalação inclui dependências. “Cancelar restantes” conclui o item em andamento e preserva os itens não executados para nova tentativa.

Experimente buscar, filtrar por perfil e estado, abrir detalhes, selecionar aplicativos e simular a instalação. O plano inclui dependências. O botão de sol alterna o tema. `/` abre a busca; `Esc` fecha detalhes.

Este protótipo não integra Go nem um framework de janela. A camada `model.js` separa catálogo, filtros, estatísticas e plano de instalação para uma integração posterior com o backend escolhido.

Testes: `node --test prototype/model.test.cjs` a partir da raiz do projeto.

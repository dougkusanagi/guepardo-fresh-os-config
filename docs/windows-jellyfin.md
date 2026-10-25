# Windows fresh install

O script `winstall-dougkusanagi-basic.ps1` instala a lista geral de aplicativos.
O modulo Jellyfin pode ser executado separadamente, sem instalar os demais apps.

## Comece aqui: Jellyfin com tema e plugins

**Nenhum parametro do modulo e obrigatorio.** O comando abaixo instala ou
reaproveita o Jellyfin local, aplica o tema e instala os seis plugins de
metadados, o Media Bar e sua dependencia File Transformation.

No PowerShell, na pasta deste projeto:

```powershell
.\jellyfin.cmd
```

O arquivo `jellyfin.cmd` prepara a chamada do PowerShell para voce. Nao precisa
digitar `-NoProfile`, `-ExecutionPolicy` ou `-File`, nem abrir o terminal como
administrador antecipadamente. Um instalador pode pedir UAC durante a instalacao.
O launcher funciona tambem no Prompt de Comando e localiza o modulo a partir
da sua propria pasta. Nao precisa informar URL, caminho do CSS ou senha na linha
de comando. A politica de execucao e ajustada apenas no processo criado.

### O que voce precisa fazer

1. Execute o comando acima na pasta deste projeto.
2. Se o servidor for novo, conclua o assistente que abrir no navegador.
3. Quando o terminal perguntar, informe o usuario e a senha de administrador
   **do Jellyfin**. A senha fica oculta enquanto voce digita.
4. Ao terminar, reinicie o Jellyfin para carregar os plugins e atualize a pagina.

O modulo instala/reaproveita `Jellyfin.Server` pelo Winget e aguarda o servidor
em `http://localhost:8096`. Se existir um servico Jellyfin parado, tenta inicia-lo;
se necessario, abra Jellyfin pelo menu Iniciar. Alguns instaladores pedem UAC.
Em um servidor novo, abre o assistente no navegador: crie sua conta e configure
as bibliotecas. O modulo aguarda ate dez minutos e depois pede, no terminal,
a conta de administrador do **Jellyfin**, criada no assistente (nao a conta do
Windows), para aplicar `jellyfin/polish.css`. A senha e o token nao sao
salvos em arquivos; a sessao temporaria e encerrada ao terminar.

Tambem instala AniDB, AniList, AniSearch, Kitsu, Artwork e Cover Art Archive
pelo catalogo oficial, selecionando a versao compativel com seu servidor.
Preserva outros repositorios e reaproveita plugins ja instalados. Ao terminar,
reinicie o Jellyfin para carregar os plugins e pressione **Ctrl+Shift+R** para
recarregar a interface e ver o banner no topo. Se algum falhar, os demais sao
tentados e o modulo informa a falha; execute novamente depois de corrigir.
Nas configuracoes de cada biblioteca, escolha os provedores de metadados e
imagens desejados. Instalar plugins nao altera a ordem dos provedores nem
substitui uma eventual configuracao especifica exigida por eles.

Quando o Jellyfin estiver instalado como servico, o aviso final mostra o nome
detectado e o comando para reinicia-lo. Abra um **PowerShell como administrador**
e execute, por exemplo:

```powershell
Restart-Service -Name 'JellyfinServer'
```

Nao precisa de icone na tray. Aguarde o servidor voltar e pressione
**Ctrl+Shift+R** no navegador. O modulo informa o comando; nao reinicia o servidor
automaticamente.

O banner usa **Media Bar** e **File Transformation**, do repositorio do autor
`https://www.iamparadox.dev/jellyfin/plugins/manifest.json`. O modulo instala
essas dependencias automaticamente, sem editar o `index.html` do Jellyfin.
Seleciona os ZIPs para a linha exata do servidor e usa um catalogo temporario
em loopback para evitar que pacotes de Jellyfin 10.x sejam escolhidos em 12.x
quando possuem o mesmo numero de versao. Os repositorios originais sao
restaurados ao terminar; execute novamente o modulo para atualizar essas duas
dependencias. Esse fluxo requer executar no computador do Jellyfin usando
`localhost`; para servidor remoto, use `-SkipPlugins` para aplicar apenas o CSS.

### Jellyfin ja instalado

O comando principal tambem funciona. Para pular a etapa do Winget, use:

```powershell
.\jellyfin.cmd -SkipInstall
```

### Parametros opcionais

Use apenas quando precisar mudar o comportamento padrao. Passe as opcoes
diretamente para `jellyfin.cmd`, como nos exemplos abaixo.

| Parametro | Quando usar | Padrao |
| --- | --- | --- |
| `-SkipInstall` | Pular a instalacao pelo Winget | Instala/reaproveita o servidor |
| `-SkipPlugins` | Aplicar o tema sem instalar plugins | Instala metadados, Media Bar e File Transformation |
| `-WhatIf` | Mostrar a acao sem alterar o sistema | Executa as acoes |
| `-Restore` | Recuperar o CSS anterior; nao instala nem remove plugins | Aplica o tema |
| `-ServerUrl` | Usar outra porta, caminho ou servidor | `http://localhost:8096` |
| `-ApiKey` | Autenticar com uma chave de API como `SecureString` | Pede login no terminal |
| `-Credential` | Passar uma conta como `PSCredential` | Pede login no terminal |
| `-TimeoutSeconds` | Mudar a espera pelo servidor e assistente (1 a 3600 segundos) | `600` |
| `-CssPath` | Aplicar outro arquivo CSS | `jellyfin/polish.css` deste repo |
| `-BackupDirectory` | Escolher onde salvar o CSS anterior | `%LOCALAPPDATA%\WindowsFreshInstall\Jellyfin` |

Use `-ApiKey` ou `-Credential`, nunca os dois juntos.

### Exemplos

```powershell
# Mostrar a acao sem instalar, abrir navegador ou chamar a API.
.\jellyfin.cmd -WhatIf

# Aplicar somente o tema, sem instalar plugins.
.\jellyfin.cmd -SkipInstall -SkipPlugins

# Usar uma chave criada em Dashboard > Advanced > API Keys, sem login de usuario.
# Objetos SecureString/PSCredential exigem chamada direta no PowerShell.
$key = Read-Host 'Chave de API do Jellyfin' -AsSecureString
.\modules\jellyfin.ps1 -SkipInstall -ApiKey $key

# Fornecer a conta antecipadamente e aumentar a espera pelo assistente.
.\modules\jellyfin.ps1 -SkipInstall -Credential (Get-Credential) -TimeoutSeconds 1200

# Restaurar o CSS que existia antes da primeira aplicacao.
.\jellyfin.cmd -Restore

# Aplicar em outro servidor (HTTPS obrigatorio para enderecos remotos).
.\jellyfin.cmd -SkipInstall -ServerUrl https://media.example.com/jellyfin
```

### Credenciais do Jellyfin e permissoes do Windows

A autenticacao na API e independente da elevacao do Windows. Abrir PowerShell
como administrador, ou usar `sudo` no Windows 11 24H2+ com o recurso habilitado,
permite operacoes de sistema, mas nao autentica no Jellyfin. Para executar sem
pedir usuario e senha, passe `-ApiKey` ou `-Credential` previamente obtidos.
`-Restore` restaura apenas o CSS; nao remove plugins.

Se ocorrer erro HTTP, o modulo informa o metodo e o endpoint que falhou.
`Users/AuthenticateByName` indica falha no login; erro em outro endpoint ocorre
depois dele. O modulo envia o token em `Authorization`, incluindo suporte ao
Jellyfin 12 com autenticacao legada desabilitada.

### Backup e restauracao

O primeiro CSS anterior fica salvo em
`%LOCALAPPDATA%\WindowsFreshInstall\Jellyfin\<id-do-servidor>.json`.
Reaplicar o modulo preserva esse backup. Restaurar altera somente o CSS e
preserva as outras configuracoes atuais de branding. Atualize a pagina depois
de aplicar ou restaurar.

### Sobre o tema

O CSS foi copiado de `guepardo-fresh-os-config/jellyfin/polish.css`: GlassFin
mais os ajustes locais. Os imports originais usam `latest` e `main`, dependem
de acesso ao jsDelivr pelos clientes e podem mudar independentemente deste repo.
O CSS estiliza o Media Bar; o modulo instala o componente e sua dependencia.
Os destaques precisam de itens na biblioteca e imagens de fundo disponiveis.
O tema afeta clientes que usam Jellyfin Web; aplicativos nativos podem ter sua
propria interface. Consulte a [documentacao do Jellyfin](https://jellyfin.org/docs/general/clients/css-customization/).

## Verificacao local

```powershell
powershell -NoProfile -File .\tests\jellyfin.tests.ps1
powershell -NoProfile -File .\tests\jellyfin-plugins.tests.ps1
powershell -NoProfile -File .\tests\jellyfin-http.tests.ps1
powershell -NoProfile -File .\tests\jellyfin-banner.tests.ps1
```

Os testes simulam Winget e a API; nao instalam aplicativos nem alteram Jellyfin.

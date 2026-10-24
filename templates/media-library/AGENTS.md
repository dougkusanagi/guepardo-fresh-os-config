# Biblioteca de animes (Jellyfin + qBittorrent) — notas informativas

Esta pasta é uma biblioteca do Jellyfin e também a pasta de seed do qBittorrent.

O Jellyfin trata cada pasta de primeiro nível como uma série e espera `Série/Season 01/Série - S01E01.ext`. Pastas de torrent fora desse padrão (uma por temporada, nomes de fansub, versões duplicadas) apareciam separadas ou mal identificadas. Renomear ou mover arquivos que estão em seed quebra o seed.

Por isso, em vários animes foram criadas estruturas organizadas com **hardlinks** (mesmo arquivo, outro nome, sem ocupar espaço extra), e as pastas originais do torrent receberam um arquivo `.ignore` para o Jellyfin não listá-las em duplicidade. Os arquivos originais não foram alterados. Alguns animes sem seed foram simplesmente movidos/renomeados.

Se for mexer aqui: confira se o torrent está em seed antes de mover, renomear ou apagar; remover um `.ignore` faz a pasta original reaparecer no Jellyfin; novos downloads com o mesmo problema podem receber o mesmo tratamento. Após mudanças, é preciso escanear a biblioteca na interface do Jellyfin.

Observação: o `.ignore` funcionou para pastas presentes desde o primeiro escaneamento, mas não removeu séries que o Jellyfin já conhecia nem impediu que elas voltassem. Nesses casos, as pastas originais (sem seed) foram movidas para uma pasta irmã, `../animes-fora-da-biblioteca/` (ou outro destino fora da biblioteca), fora da biblioteca. Os arquivos continuam existindo; as versões organizadas são hardlinks.

# Fontes Abertas de Odds 2026

Gerado em: 2026-06-13

## Objetivo

Encontrar uma fonte aberta, reproduzivel e sem compra de API key para odds 1X2 dos jogos da Copa do Mundo 2026, pelo menos na fase de grupos.

## Resultado

Nao foi identificada uma API aberta sem chave que entregue odds 1X2 por jogo da fase final da Copa 2026.

## Fontes avaliadas

### football-data.co.uk

Status: usar como fonte aberta primaria quando houver cobertura.

O arquivo `https://www.football-data.co.uk/WorldCup2026.xlsx` e baixavel sem chave e foi integrado ao pipeline. Em 2026-06-13, ele contem odds da Copa 2022 e dados de eliminatorias, mas nao odds dos jogos da fase final da Copa 2026.

### The Odds API

Status: descartada para V1.

A API cobre `soccer_fifa_world_cup`, mas exige API key e pode exigir plano pago. Como a regra do projeto e trabalhar com dados abertos sem compra de chave, ela nao deve ser dependencia da coleta V1.

### OddsChecker

Status: scraper implementado com ressalvas.

O site exibe odds da fase de grupos e links por jogo, por exemplo `https://www.oddschecker.com/br/futebol/internacional/copa-do-mundo-fifa/brazil-v-morocco`. Foi criado o script `R/01_coleta/07b_baixar_odds_oddschecker.R` para tentar extrair o mercado `Vencedor`/1X2 por casa.

Limitacao: requisicoes HTTP simples podem receber bloqueio Cloudflare. O script registra `cloudflare_blocked` em `data/raw/metadata/oddschecker_status.csv` e nao inventa odds quando isso acontece. Existe um modo opcional com `chromote` (`ODDSCHECKER_USE_CHROMOTE=true`) para ambientes em que o navegador headless consiga renderizar a pagina, mas ele tambem pode ser bloqueado.

Modo recomendado para automacao R assistida:

1. Abrir um Chrome normal com DevTools remoto, usando um perfil temporario.
2. Navegar normalmente para o OddsChecker nesse Chrome.
3. Rodar o script com `ODDSCHECKER_USE_CHROMOTE=true` e `ODDSCHECKER_REMOTE_DEBUGGING_PORT=9222`.

Exemplo:

```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --remote-debugging-port=9222 \
  --user-data-dir=/tmp/oddschecker-chrome-profile

ODDSCHECKER_USE_CHROMOTE=true \
ODDSCHECKER_REMOTE_DEBUGGING_PORT=9222 \
Rscript R/01_coleta/07b_baixar_odds_oddschecker.R
```

Esse modo ainda respeita o comportamento do site: se houver bloqueio/intersticial, a coleta registra status e nao tenta contornar protecoes.

### OddsPortal / OddsAgora

Status: nao usar como coleta automatica V1 por enquanto.

Pode exibir odds e historico publicamente, mas nao foi adotado como fonte automatica porque nao ha API aberta documentada sem chave para coleta reproduzivel, e scraping precisa validacao de termos de uso.

## Decisao V1

Manter odds 2022 vindas de `football-data.co.uk`.

Tentar OddsChecker como fonte aberta por scraping auditavel. Se o site bloquear a coleta automatica, manter odds 2026 como ausentes e auditadas ate que uma fonte aberta sem chave esteja disponivel ou ate `football-data.co.uk` atualize o arquivo com odds dos jogos da fase final da Copa 2026.

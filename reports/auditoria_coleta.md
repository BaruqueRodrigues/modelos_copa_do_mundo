# Auditoria da Coleta

Gerado em: 2026-06-15T14:32:54-0300

## Resumo

# A tibble: 2 × 8
   year n_jogos n_jogos_com_placar n_jogos_sem_data n_times_distintos
  <dbl>   <int>              <int>            <int>             <int>
1  2022      64                 64                0                32
2  2026     104                 12                0               112
# ℹ 3 more variables: n_duplicatas <int>, n_jogos_sem_odds <int>,
#   n_odds_invalidas <int>

## Pendencias

- Jogos finalizados sem odds ligadas: 4. Ver `data/raw/metadata/jogos_sem_odds.csv`.

# ISI — Trabalho Prático I
### Monitorização contínua de preços de combustíveis em Portugal

Unidade curricular: **Integração de Sistemas de Informação [11301]** · 2026/27 · UPCA/EST Barcelos
Trabalho **individual** · Entrega: **22/10/2026** (e-learning)

---

## 1. Problema

Os preços dos combustíveis são publicados posto a posto pela DGEG, mas estão dispersos e chegam
como **texto em português** (`"0,849 €"`). Este trabalho constrói um processo **ETL** que recolhe todos
os postos do país, trata e normaliza os dados, cruza fontes e transforma o resultado em decisão: preço
médio/mínimo/máximo por distrito e por combustível, desvio à média nacional, histórico entre execuções e
alerta por email quando um distrito fica abaixo do preço-alvo definido.

## 2. Arquitetura

```
   (E1) E1_extrair_api        (E2) E2_carregar_staging      (T) T1_transformar        (L) L1_carregar_modelo
   API DGEG (JSON)  -->  ficheiros CSV/XML/JSON  -->  staging_preco  -->  regex, unidade,   -->  dim_*, fact_preco,
   PrecoComb              zona de aterragem          (PostgreSQL)       agrupamentos           agg_*, exportações
   (1 chamada HTTP)       snapshot datado                               validações             email + dashboard
                     \___________________ Job: JOB_TP1.kjb (E1 -> E2 -> T1 -> L1) ___________________/
```

Só a **E1** toca a rede. A API é contactada **uma vez por execução** e o resultado fica em ficheiros datados
(a zona de aterragem); tudo o resto lê esses ficheiros. Com a API em baixo corre-se `E2 -> T1 -> L1` sobre o
último snapshot e as fases T e L continuam a produzir modelo, exportações e dashboard — perde-se apenas a
actualização do dia.

## 3. Ferramentas

| Ferramenta | Papel |
|---|---|
| **Pentaho Data Integration CE 10.2 (Kettle/Spoon)** | motor ETL (E, T e L) |
| **PostgreSQL 17** (+ pgAdmin 4) | base de dados: staging, modelo dimensional e histórico |
| **Grafana** | dashboards sobre o PostgreSQL (fase de visualização) |
| **Git** | versionamento de todo o material |

## 4. Fontes de dados

| Fonte | Formato | Endpoint |
|---|---|---|
| DGEG — PreçoComb, preços posto a posto | JSON (REST) | `precoscombustiveis.dgeg.gov.pt/api/PrecoComb/PesquisarPostos` |
| DGEG — distritos/concelhos | JSON (REST) | `.../api/PrecoComb/GetDistritos`, `/GetMunicipios` |
| Preços-alvo por distrito (configuração, criada por nós) | CSV | `dados/limiares-distrito.csv` |

Uma única chamada à DGEG devolve **~14 000 linhas** (≈3 100 postos × 14 combustíveis) em ~1,4 s, sem chave de
API. O total **muda ao longo do dia** (14 073 → 13 957 → 14 053), por isso cada execução é datada e guardada em
`dados/snapshot-<data>/`; o snapshot incluído neste repositório é o de **12/10/2026 (14 053 linhas)**.

## 5. Estrutura do repositório

```
kettle/      transformações (.ktr) e, mais tarde, o job (.kjb)
sql/         DDL do modelo de dados (tabelas, chaves, índices)
dados/       snapshot datado da API (CSV + XML + JSON), preços-alvo e exportações de dados/out/
relatorio/   relatório final (documento, imagens e diagramas)
videos/      vídeo de demonstração antes do upload
```

## 6. Como executar

1. Instalar Java 21, Pentaho Data Integration CE 10.2 e PostgreSQL 17; criar a base `isi_tp1`.
2. Criar o modelo: correr `sql/00_ddl.sql` no pgAdmin (a base `isi_tp1`).
3. **(E1)** `kettle/E1_extrair_api.ktr` — chama a API uma vez, escreve o snapshot do dia em
   `dados/snapshot-<data>/` (CSV + XML + JSON) e a linha de auditoria em `execucao`.
4. **(E2)** `kettle/E2_carregar_staging.ktr` — carrega esse CSV em `staging_preco`.
   *Se a API estiver em baixo: saltar a E1 e correr só a E2 sobre o último snapshot — o resto do processo não usa a rede.*
5. **(T)** `kettle/T1_transformar.ktr` — transforma e agrega (ver §7).
6. **(L)** `kettle/L1_carregar_modelo.ktr` e o job `kettle/JOB_TP1.kjb` — em construção.

## 7. Estado do trabalho

| Fase | Estado | O que faz |
|---|---|---|
| **E — Recolha e preparação** | concluída | `E1` (API → snapshot CSV/XML/JSON + auditoria) e `E2` (snapshot → `staging_preco`, sem rede) |
| **T — Processamento e transformação** | concluída | `T1`: leitura do staging, regex do preço (`"0,849 €"` → número), ramo de validação, unidade derivada do nome do combustível, cálculo do preço e normalização da marca, agrupamento por distrito × combustível (contagem, média, mínimo e máximo) e cruzamento com os preços-alvo |
| **L — Persistência, exportação e notificações** | em construção | carga do modelo dimensional, exportações (XML/JSON/CSV/SQL), email de alerta e dashboard |

Números da execução de 12/10: **14 053 linhas** transformadas → **208 agregados** por distrito × combustível ×
unidade (189 dos quais €/litro; GNC e GNL, que são €/kg e €/m³, nunca entram nas mesmas médias) → **4 distritos
abaixo do preço-alvo** definido.

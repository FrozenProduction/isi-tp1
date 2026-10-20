# ISI: Trabalho Prático I
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
   (E1) E1_extrair_api        (E2) E2_carregar_staging      (T) T1_transformar        (L) L1_carregar_dimensoes
   API DGEG (JSON)  -->  ficheiros CSV/XML/JSON  -->  staging_preco  -->  regex, unidade,   -->  dim_*, fact_preco,
   PrecoComb              zona de aterragem          (PostgreSQL)       agrupamentos           agg_*, exportações
   (1 chamada HTTP)       snapshot datado                               validações             email + dashboard
            \______ Job: JOB_TP1.kjb (E1 -> E2 -> T1 -> L1..L6 -> relatório HTML -> email) ______/
```

Só a **E1** toca a rede. A API é contactada **uma vez por execução** e o resultado fica em ficheiros datados
(a zona de aterragem); tudo o resto lê esses ficheiros. Com a API em baixo corre-se `E2 -> T1 -> L1` sobre o
último snapshot e as fases T e L continuam a produzir modelo, exportações e dashboard: perde-se apenas a
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
| DGEG: PreçoComb, preços posto a posto | JSON (REST) | `precoscombustiveis.dgeg.gov.pt/api/PrecoComb/PesquisarPostos` |
| DGEG: distritos/concelhos | JSON (REST) | `.../api/PrecoComb/GetDistritos`, `/GetMunicipios` |
| Preços-alvo por combustível (configuração, criada por nós) | CSV | `dados/limiares-combustivel.csv` |

Uma única chamada à DGEG devolve **~14 000 linhas** (≈3 100 postos × 14 combustíveis) em ~1,4 s, sem chave de
API. O total **muda ao longo do dia** (14 073 → 13 957 → 14 053), por isso cada execução é datada e guardada em
`dados/snapshot-<data>/`; o snapshot incluído neste repositório é o de **19/10/2026 (14 213 linhas)**.

O preço-alvo é **por combustível** e não por distrito: o alvo de 2,200 €/L é um alvo de gasóleo, e compará-lo com
o GPL (≈1,00 €/L) ou com um gasóleo colorido daria alertas falsos. Os três combustíveis de estrada têm alvo
próprio (média nacional da execução de referência, menos 1 cêntimo) e os restantes não têm alvo: deixam de
disparar alerta.

## 5. Estrutura do repositório

```
kettle/      transformações (.ktr), o job (.kjb) e a folha XSL do relatório (relatorio.xsl)
sql/         DDL do modelo de dados (tabelas, chaves, índices)
dados/       snapshot datado da API (CSV + XML + JSON), preços-alvo e exportações de dados/out/
relatorio/   relatório final (documento, imagens e diagramas)
videos/      vídeo de demonstração antes do upload

grafana-dashboard.json   dashboard do Grafana exportado (importável: Dashboards -> New -> Import)
```

## 6. Como executar

> **Antes da primeira execução, a configuração fica fora do repositório:** a ligação à base usa `${DB_PASSWORD}`;
> define-a no teu `KETTLE_HOME/.kettle/kettle.properties` (`DB_PASSWORD = <password do postgres>`). Nenhum
> ficheiro deste repositório guarda a password. As fases E1/E2 leem o parâmetro `SNAPSHOT_DIR` (predefinição
> `snapshot-2026-10-19`), por isso mudar de dia é um valor, não três caminhos.

1. Instalar Java 21, Pentaho Data Integration CE 10.2 e PostgreSQL 17; criar a base `isi_tp1`.
2. Criar o modelo: correr `sql/00_ddl.sql` no pgAdmin (a base `isi_tp1`).
3. **(E1)** `kettle/E1_extrair_api.ktr`: chama a API uma vez, escreve o snapshot do dia em
   `dados/snapshot-<data>/` (CSV + XML + JSON) e a linha de auditoria em `execucao`.
4. **(E2)** `kettle/E2_carregar_staging.ktr`: carrega esse CSV em `staging_preco`.
   *Se a API estiver em baixo: saltar a E1 e correr só a E2 sobre o último snapshot: o resto do processo não usa a rede.*
5. **(T)** `kettle/T1_transformar.ktr`: transforma e agrega (ver §7).
6. **(L)** carregar o modelo dimensional e exportar: `L1` dimensões, `L2` concelhos, `L3` postos,
   `L4` factos + agregados + desvio à média nacional, `L5` exportações XML/JSON/CSV/SQL,
   `L6` corpo HTML do email de resumo.

### Correr o job completo (a forma recomendada)

Abrir `kettle/JOB_TP1.kjb` no Spoon e executar (Play). O job corre, por esta ordem:
`E1 -> E2 -> T1 -> L1 -> L2 -> L3 -> L4 -> L5 -> L6`, gera o **relatório HTML** a partir do XML exportado
(entrada *XSL transformation* com `kettle/relatorio.xsl`), envia o **email de resumo** (e um **email de erro**
se alguma fase falhar, por hop vermelho) e **fecha a execução** na tabela `execucao` (`estado = 'concluida'`,
com as contagens de linhas lidas e carregadas).

**Configuração fora do repositório** (`KETTLE_HOME/.kettle/kettle.properties`): nenhum destes valores vive no repositório.

| Variável | O que é |
|---|---|
| `DB_PASSWORD` | password do PostgreSQL (base `isi_tp1`) |
| `MAIL_TO` | destinatário do email de resumo/alerta |
| `MAIL_USER` | conta SMTP que envia (ex.: `nome@alunos.ipca.pt`) |
| `MAIL_PASSWORD` | password/authorization code dessa conta SMTP |

O servidor de email do job é `smtp.office365.com:587` (TLS): serve as contas `@alunos.ipca.pt`; para outra
conta muda-se o `server`/`port` nas entradas *Enviar email*. Sem as variáveis `MAIL_*` o ETL corre até ao fim
(a `execucao` fica fechada) mas o envio do email falha.

## 7. Estado do trabalho

| Fase | Estado | O que faz |
|---|---|---|
| **E: Recolha e preparação** | concluída | `E1` (API → snapshot CSV/XML/JSON + auditoria) e `E2` (snapshot → `staging_preco`, sem rede) |
| **T: Processamento e transformação** | concluída | `T1` (15 passos): leitura do staging, **remoção de duplicados** (`Unique` por posto × combustível), **identificação de valores nulos** (os postos sem código postal saem em `dados/out/nulos.csv`, com o campo em falta: as linhas não se perdem), regex do preço (`"0,849 €"` → número), ramo de validação, unidade derivada do nome do combustível, cálculo do preço e normalização da marca, agrupamento por distrito × combustível (contagem, média, mínimo e máximo) e cruzamento com o preço-alvo do próprio combustível |
| **L: Persistência, exportação e notificações** | concluída | `L1` dimensões (18 distritos · 14 combustíveis · 55 marcas) · `L2` concelhos (277) · `L3` postos (3 143) · `L4` factos (14 213 preços) + agregados (208) + desvio à média nacional · `L5` exportações XML/JSON/CSV/SQL · `L6` corpo HTML do email |
| **Orquestração** | concluída | `JOB_TP1.kjb`: `E1 -> E2 -> T1 -> L1..L6`, relatório HTML por XSLT sobre o XML exportado, email de resumo (alertas em destaque) e de erro, fecho da tabela `execucao` |
| **Visualização e entrega** | parcial | dashboard **Grafana** sobre o modelo (4 painéis + 3 indicadores) e relatório final em PDF (8 secções) concluídos; falta o **vídeo** com QR Code, o empacotamento do ZIP e a submissão no e-learning |

Números da execução de 19/10 (run 25, a que este repositório corresponde): **14 213 linhas** lidas → **0 duplicados**
removidos (o passo existe e é a garantia explícita) → **10 linhas** identificadas com código postal em falta na
origem (2 postos de Viseu, listados em `nulos.csv`) → **14 213 linhas** limpas → **208 agregados** por distrito ×
combustível × unidade (189 dos quais €/litro; GNC e GNL, que são €/kg e €/m³, nunca entram nas mesmas médias) →
**54 grupos** com preço-alvo (3 combustíveis de estrada × 18 distritos) → **2 alertas** abaixo do alvo do combustível:

| Distrito | Combustível | Postos | Preço médio | Alvo |
|---|---|---|---|---|
| Braga | Gasolina simples 95 | 257 | 2,135 € | 2,140 € |
| Coimbra | GPL Auto | 26 | 0,992 € | 1,000 € |

-- =====================================================================
--  TP1 ISI - modelo de dados (PostgreSQL 17)
--  Executar no pgAdmin: base isi_tp1 > Query Tool > abrir este ficheiro > F5
--  O script é re-executável: faz DROP antes de criar.
-- =====================================================================

DROP VIEW  IF EXISTS vw_ranking_distrito CASCADE;
DROP TABLE IF EXISTS fact_preco CASCADE;
DROP TABLE IF EXISTS agg_distrito_combustivel CASCADE;
DROP TABLE IF EXISTS dim_posto CASCADE;
DROP TABLE IF EXISTS dim_marca CASCADE;
DROP TABLE IF EXISTS dim_combustivel CASCADE;
DROP TABLE IF EXISTS dim_concelho CASCADE;
DROP TABLE IF EXISTS dim_distrito CASCADE;
DROP TABLE IF EXISTS staging_preco CASCADE;
DROP TABLE IF EXISTS execucao CASCADE;

-- 0) Auditoria: uma linha por execução do job (logs em tabela)
CREATE TABLE execucao (
  run_id              serial PRIMARY KEY,
  iniciada_em         timestamp NOT NULL DEFAULT now(),
  terminada_em        timestamp,
  origem              text      NOT NULL DEFAULT 'DGEG PrecoComb',
  n_linhas_lidas      integer,
  n_linhas_carregadas integer,
  estado              text      NOT NULL DEFAULT 'a correr'
);

-- 1) Staging: o dado CRU, tal como a API o devolve (sem transformação)
CREATE TABLE staging_preco (
  run_id           integer NOT NULL REFERENCES execucao(run_id) ON DELETE CASCADE,
  id_posto         integer NOT NULL,
  nome             text,
  tipo_posto       text,
  marca            text,
  combustivel      text,
  preco_texto      text,            -- como vem da API: '0,849 €'
  distrito         text,
  concelho         text,
  morada           text,            -- atenção: contém quebras de linha reais
  localidade       text,
  cod_postal       text,            -- texto de propósito: '4780-219' não é número
  latitude         text,   -- cru, de propósito: o JSON traz ponto decimal e o Kettle converte
  longitude        text,   -- Number segundo o locale do Windows (16 valores em 13 944 saem errados);
                           -- a conversão para número é feita na fase T, com cast explícito
  data_atualizacao text,            -- '2026-10-06 09:00' -> convertido no T
  PRIMARY KEY (run_id, id_posto, combustivel)
);

-- 2) Dimensões
CREATE TABLE dim_distrito (
  distrito_id serial PRIMARY KEY,
  nome        text NOT NULL UNIQUE
);

CREATE TABLE dim_concelho (
  concelho_id serial PRIMARY KEY,
  nome        text NOT NULL,
  distrito_id integer NOT NULL REFERENCES dim_distrito(distrito_id),
  UNIQUE (nome, distrito_id)
);

CREATE TABLE dim_marca (
  marca_id      serial PRIMARY KEY,
  nome          text NOT NULL UNIQUE,   -- normalizado (maiúsculas, sem espaços extra)
  nome_original text
);

CREATE TABLE dim_combustivel (
  combustivel_id serial PRIMARY KEY,
  nome           text NOT NULL UNIQUE,  -- ex.: 'Gasóleo simples'
  unidade        text NOT NULL CHECK (unidade IN ('litro','kg','m3'))
);

-- 3) Dimensão posto (o Id da DGEG é estável entre execuções -> serve de chave)
CREATE TABLE dim_posto (
  posto_id     integer PRIMARY KEY,
  nome         text NOT NULL,
  morada       text,
  localidade   text,
  cod_postal   text,
  latitude     numeric(9,6),
  longitude    numeric(9,6),
  marca_id     integer REFERENCES dim_marca(marca_id),
  concelho_id  integer REFERENCES dim_concelho(concelho_id),
  atualizado_em timestamp NOT NULL DEFAULT now()
);

-- 4) Facto: uma linha por posto x combustível x execução -> constrói o histórico
CREATE TABLE fact_preco (
  run_id            integer NOT NULL REFERENCES execucao(run_id) ON DELETE CASCADE,
  posto_id          integer NOT NULL REFERENCES dim_posto(posto_id),
  combustivel_id    integer NOT NULL REFERENCES dim_combustivel(combustivel_id),
  preco             numeric(6,3) NOT NULL CHECK (preco > 0 AND preco < 100),
  data_atualizacao  timestamp,
  PRIMARY KEY (run_id, posto_id, combustivel_id)
);

CREATE INDEX idx_fact_preco_data ON fact_preco (data_atualizacao);
CREATE INDEX idx_fact_preco_comb ON fact_preco (combustivel_id);

-- 5) Agregado calculado pelo job (a tabela que o dashboard lê)
CREATE TABLE agg_distrito_combustivel (
  run_id                integer NOT NULL REFERENCES execucao(run_id) ON DELETE CASCADE,
  distrito_id           integer NOT NULL REFERENCES dim_distrito(distrito_id),
  combustivel_id        integer NOT NULL REFERENCES dim_combustivel(combustivel_id),
  n_postos              integer NOT NULL,
  preco_medio           numeric(6,3) NOT NULL,
  preco_min             numeric(6,3) NOT NULL,
  preco_max             numeric(6,3) NOT NULL,
  desvio_media_nacional numeric(6,3),
  PRIMARY KEY (run_id, distrito_id, combustivel_id)
);

-- 6) Vista de apoio ao relatório e ao dashboard (só combustíveis por litro)
CREATE VIEW vw_ranking_distrito AS
SELECT e.iniciada_em::date AS data_execucao,
       d.nome              AS distrito,
       c.nome              AS combustivel,
       a.n_postos,
       a.preco_min,
       a.preco_medio,
       a.preco_max,
       a.desvio_media_nacional
FROM agg_distrito_combustivel a
JOIN dim_distrito d      ON d.distrito_id   = a.distrito_id
JOIN dim_combustivel c   ON c.combustivel_id = a.combustivel_id
JOIN execucao e          ON e.run_id         = a.run_id
WHERE c.unidade = 'litro'
ORDER BY a.preco_medio;

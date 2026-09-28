-- =========================================================
-- 05_explain_analyze.sql - O PostgreSQL usa mesmo os índices?
--
-- EXPLAIN ANALYZE EXECUTA a consulta de verdade e mostra o plano real
-- (tempo, linhas, buffers). BUFFERS mostra quantas páginas de 8 kB foram
-- lidas (shared hit = cache, read = disco).
--
-- Cada consulta roda duas vezes: COM o índice e SEM ele. Como o DDL do
-- PostgreSQL é transacional, o "sem índice" é feito assim:
--     BEGIN; DROP INDEX ...; EXPLAIN ANALYZE ...; ROLLBACK;
-- e o índice volta intacto após o ROLLBACK.
-- =========================================================

SET search_path TO express;
VACUUM (ANALYZE) table_bebidas, table_clientes, table_valor, table_comercio;  -- estatísticas e resumos BRIN frescos (a etapa 04 alterou dados)

-- ---------------------------------------------------------
-- Q1 - Últimos 10 pedidos de um cliente (tela de atendimento)
--      Índice esperado: idx_comercio_cliente_data (id_cliente, data_pedido DESC)
-- ---------------------------------------------------------
\echo
\echo '##### Q1 COM indice #####'
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id_pedido, p.data_pedido, b.nome, p.quantidade, p.valor_total, p.status_entrega
FROM table_comercio p
JOIN table_bebidas  b ON b.id_bebida = p.id_bebida
WHERE p.id_cliente = 4321
ORDER BY p.data_pedido DESC
LIMIT 10;

\echo
\echo '##### Q1 SEM indice (DROP INDEX dentro de transacao + ROLLBACK) #####'
BEGIN;
DROP INDEX idx_comercio_cliente_data;
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id_pedido, p.data_pedido, b.nome, p.quantidade, p.valor_total, p.status_entrega
FROM table_comercio p
JOIN table_bebidas  b ON b.id_bebida = p.id_bebida
WHERE p.id_cliente = 4321
ORDER BY p.data_pedido DESC
LIMIT 10;
ROLLBACK;

-- ---------------------------------------------------------
-- Q2 - Fila de entregas em aberto, mais antigas primeiro (roteirização)
--      Índice esperado: idx_comercio_em_aberto (parcial)
-- ---------------------------------------------------------
\echo
\echo '##### Q2 COM indice parcial #####'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id_pedido, id_cliente, status_entrega, data_pedido
FROM table_comercio
WHERE status_entrega IN ('Pendente', 'Em rota')
ORDER BY data_pedido;

\echo
\echo '##### Q2 SEM indice parcial #####'
BEGIN;
DROP INDEX idx_comercio_em_aberto;
EXPLAIN (ANALYZE, BUFFERS)
SELECT id_pedido, id_cliente, status_entrega, data_pedido
FROM table_comercio
WHERE status_entrega IN ('Pendente', 'Em rota')
ORDER BY data_pedido;
ROLLBACK;

-- ---------------------------------------------------------
-- Q3 - Faturamento por dia dos últimos 7 dias (relatório por período)
--      Índice esperado: idx_comercio_data_brin (BRIN)
-- ---------------------------------------------------------
\echo
\echo '##### Q3 COM BRIN #####'
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('day', data_pedido) AS dia, count(*) AS pedidos, sum(valor_total) AS faturamento
FROM table_comercio
WHERE data_pedido >= now() - interval '7 days'
GROUP BY 1
ORDER BY 1;

\echo
\echo '##### Q3 SEM BRIN #####'
BEGIN;
DROP INDEX idx_comercio_data_brin;
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('day', data_pedido) AS dia, count(*) AS pedidos, sum(valor_total) AS faturamento
FROM table_comercio
WHERE data_pedido >= now() - interval '7 days'
GROUP BY 1
ORDER BY 1;
ROLLBACK;

-- ---------------------------------------------------------
-- Q4 - Clientes ativos de um bairro (roteirização por região)
--      Índice esperado: idx_clientes_cidade_bairro (parcial: WHERE ativo)
-- ---------------------------------------------------------
\echo
\echo '##### Q4 COM indice #####'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id_cliente, nome, telefone
FROM table_clientes
WHERE ativo AND cidade = 'Campinas' AND bairro = 'Bairro 07';

\echo
\echo '##### Q4 SEM indice #####'
BEGIN;
DROP INDEX idx_clientes_cidade_bairro;
EXPLAIN (ANALYZE, BUFFERS)
SELECT id_cliente, nome, telefone
FROM table_clientes
WHERE ativo AND cidade = 'Campinas' AND bairro = 'Bairro 07';
ROLLBACK;

-- ---------------------------------------------------------
-- Q5 - Total vendido de uma bebida (FK id_bebida)
--      Índice esperado: idx_comercio_bebida
-- ---------------------------------------------------------
\echo
\echo '##### Q5 COM indice #####'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) AS pedidos, sum(quantidade) AS unidades, sum(valor_total) AS faturamento
FROM table_comercio
WHERE id_bebida = 42;

\echo
\echo '##### Q5 SEM indice #####'
BEGIN;
DROP INDEX idx_comercio_bebida;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) AS pedidos, sum(quantidade) AS unidades, sum(valor_total) AS faturamento
FROM table_comercio
WHERE id_bebida = 42;
ROLLBACK;

-- ---------------------------------------------------------
-- Q6 - Contra-exemplo: tabela pequena. Filtrar bebidas por categoria.
--      Não há índice em table_bebidas.categoria de propósito: com 400 linhas
--      o Seq Scan é o plano ótimo (a tabela cabe em ~6 páginas).
-- ---------------------------------------------------------
\echo
\echo '##### Q6 (sem indice, por decisao de projeto) #####'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id_bebida, nome, estoque_atual
FROM table_bebidas
WHERE categoria = 'Cerveja' AND ativo AND estoque_atual <= estoque_minimo;

-- Conferência: os índices continuam todos no lugar após os ROLLBACKs
SELECT indexname FROM pg_indexes WHERE schemaname = 'express' ORDER BY tablename, indexname;

-- =========================================================
-- 04_transacoes.sql - Transações (ACID) com BEGIN / COMMIT /
--                     ROLLBACK / SAVEPOINT / RETURNING
--
-- EXECUTAR COM psql (usa \gset para guardar os IDs devolvidos pelo
-- RETURNING em variáveis :nome). A Transação 4 é 100% SQL e roda em
-- qualquer cliente (DBeaver, pgAdmin...).
--
-- Os erros "ERROR: ..." que aparecem na saída são PROPOSITAIS: servem
-- para mostrar o SAVEPOINT desfazendo só uma parte da transação.
-- (não use -v ON_ERROR_STOP=1 neste arquivo)
-- =========================================================

SET search_path TO express;

-- =========================================================
-- TRANSAÇÃO 1 - Novo cliente + primeiro pedido + baixa de estoque
--   Tabelas: table_clientes (INSERT), table_comercio (INSERT), table_bebidas (UPDATE)
--   Mostra: RETURNING + \gset, SAVEPOINT, ROLLBACK TO SAVEPOINT, COMMIT
--   Cenário: o vendedor digita uma quantidade MAIOR que o estoque. O CHECK
--   (estoque_atual >= 0) rejeita a baixa; só o pedido é desfeito, o cadastro
--   do cliente é preservado e o pedido é refeito com a quantidade correta.
-- =========================================================
\echo
\echo '=== TRANSACAO 1: cliente + pedido + baixa de estoque (SAVEPOINT) ==='

-- Preparação (fora da transação): escolhe uma bebida com estoque entre 50 e 100
SELECT id_bebida     AS id_bebida_t1,
       estoque_atual AS estoque_antes_t1,
       estoque_atual + 1 AS qtd_excessiva_t1
FROM table_bebidas
WHERE ativo AND estoque_atual BETWEEN 50 AND 100
ORDER BY id_bebida
LIMIT 1 \gset

BEGIN;

-- 1) Cliente novo: o ID gerado pelo SERIAL volta no RETURNING e fica em :id_cliente_t1
INSERT INTO table_clientes (nome, tipo_pessoa, cpf_cnpj, telefone, email,
                            endereco, numero, bairro, cidade, estado, cep)
VALUES ('Bar do Ze Ltda', 'Juridica', '12345678000199', '19987654321', 'contato@bardoze.com.br',
        'Rua das Flores', '120', 'Centro', 'Campinas', 'SP', '13010000')
RETURNING id_cliente AS id_cliente_t1 \gset

-- 2) Preço vigente da bebida (o id_valor será a FK do pedido)
SELECT id_valor AS id_valor_t1, preco_venda AS preco_t1
FROM table_valor
WHERE id_bebida = :id_bebida_t1 AND ativo AND data_vigencia_fim IS NULL \gset

SAVEPOINT sp_pedido;

-- 3a) Tentativa com quantidade acima do estoque
INSERT INTO table_comercio (id_cliente, id_bebida, id_valor, quantidade, valor_total, forma_pagamento)
VALUES (:id_cliente_t1, :id_bebida_t1, :id_valor_t1,
        :qtd_excessiva_t1, :qtd_excessiva_t1 * :preco_t1, 'Pix')
RETURNING id_pedido;

UPDATE table_bebidas
   SET estoque_atual = estoque_atual - :qtd_excessiva_t1     -- viola ck_bebidas_estoque
 WHERE id_bebida = :id_bebida_t1;

-- A transação está "abortada". Volta ao savepoint: o pedido some, o cliente permanece.
ROLLBACK TO SAVEPOINT sp_pedido;

-- 3b) Nova tentativa com 12 unidades
INSERT INTO table_comercio (id_cliente, id_bebida, id_valor, quantidade, valor_total, forma_pagamento)
VALUES (:id_cliente_t1, :id_bebida_t1, :id_valor_t1, 12, 12 * :preco_t1, 'Pix')
RETURNING id_pedido AS id_pedido_t1 \gset

UPDATE table_bebidas
   SET estoque_atual = estoque_atual - 12
 WHERE id_bebida = :id_bebida_t1
RETURNING id_bebida, estoque_atual AS estoque_depois;

RELEASE SAVEPOINT sp_pedido;

COMMIT;

-- Conferência pós-COMMIT: cliente e pedido gravados, estoque baixou 12 (e só 12)
SELECT c.id_cliente, c.nome, p.id_pedido, p.quantidade, p.valor_total, p.status_entrega,
       :estoque_antes_t1 AS estoque_antes, b.estoque_atual AS estoque_depois
FROM table_clientes c
JOIN table_comercio p ON p.id_cliente = c.id_cliente
JOIN table_bebidas  b ON b.id_bebida  = p.id_bebida
WHERE c.id_cliente = :id_cliente_t1;


-- =========================================================
-- TRANSAÇÃO 2 - Lançamento de produto novo (bebida + preço + 1º pedido)
--   Tabelas: table_bebidas, table_valor, table_comercio (INSERTs) + UPDATE estoque
--   Mostra: cadeia de RETURNING (id_bebida -> id_valor -> id_pedido),
--           SAVEPOINT com erro de FK composta, COMMIT
--   Cenário: por engano o pedido é lançado com o id_valor de OUTRA bebida.
--   A FK composta (id_valor, id_bebida) rejeita; corrige-se e conclui-se.
-- =========================================================
\echo
\echo '=== TRANSACAO 2: produto novo + preco + pedido (FK composta) ==='

-- Um cliente já existente para receber o pedido e um preço "errado" (de outra bebida)
SELECT id_cliente AS id_cliente_t2 FROM table_clientes WHERE ativo ORDER BY id_cliente LIMIT 1 \gset
SELECT id_valor   AS id_valor_errado_t2 FROM table_valor ORDER BY id_valor LIMIT 1 \gset

BEGIN;

INSERT INTO table_bebidas (nome, categoria, marca, embalagem, volume_ml, estoque_atual, estoque_minimo)
VALUES ('Aurora Guarana Zero 350ml', 'Refrigerante', 'Aurora', 'Lata', 350, 240, 60)
RETURNING id_bebida AS id_bebida_t2 \gset

INSERT INTO table_valor (id_bebida, preco_custo, preco_venda, data_vigencia_inicio)
VALUES (:id_bebida_t2, 2.10, 3.49, CURRENT_DATE)
RETURNING id_valor AS id_valor_t2 \gset

SAVEPOINT sp_pedido;

-- Erro proposital: id_valor de outra bebida -> viola fk_comercio_valor
INSERT INTO table_comercio (id_cliente, id_bebida, id_valor, quantidade, valor_total, forma_pagamento)
VALUES (:id_cliente_t2, :id_bebida_t2, :id_valor_errado_t2, 24, 24 * 3.49, 'Boleto');

ROLLBACK TO SAVEPOINT sp_pedido;

-- Pedido correto, com o preço recém-criado
INSERT INTO table_comercio (id_cliente, id_bebida, id_valor, quantidade, valor_total, forma_pagamento)
VALUES (:id_cliente_t2, :id_bebida_t2, :id_valor_t2, 24, 24 * 3.49, 'Boleto')
RETURNING id_pedido AS id_pedido_t2, valor_total;

UPDATE table_bebidas
   SET estoque_atual = estoque_atual - 24
 WHERE id_bebida = :id_bebida_t2
RETURNING id_bebida, estoque_atual;

COMMIT;


-- =========================================================
-- TRANSAÇÃO 3 - Reajuste de preços da categoria "Cerveja" (+8%)  -> ROLLBACK
--   Tabelas: table_valor (UPDATE encerra vigência + INSERT nova vigência)
--   Mostra: CTE com UPDATE ... RETURNING alimentando INSERT, conferência
--           antes do COMMIT e ROLLBACK total.
--   Cenário: a conferência do gestor reprova o reajuste -> nada é gravado.
-- =========================================================
\echo
\echo '=== TRANSACAO 3: reajuste de precos com ROLLBACK total ==='

SELECT count(*) AS vigencias_hoje_antes
FROM table_valor v JOIN table_bebidas b USING (id_bebida)
WHERE b.categoria = 'Cerveja' AND v.data_vigencia_inicio = CURRENT_DATE;

BEGIN;

WITH encerradas AS (
    UPDATE table_valor v
       SET data_vigencia_fim = CURRENT_DATE - 1,
           ativo = FALSE
      FROM table_bebidas b
     WHERE b.id_bebida = v.id_bebida
       AND b.categoria = 'Cerveja'
       AND v.ativo AND v.data_vigencia_fim IS NULL
    RETURNING v.id_bebida, v.preco_custo, v.preco_venda
), novas AS (
    INSERT INTO table_valor (id_bebida, preco_custo, preco_venda, data_vigencia_inicio)
    SELECT id_bebida, preco_custo, round(preco_venda * 1.08, 2), CURRENT_DATE
    FROM encerradas
    RETURNING id_valor, id_bebida, preco_venda
)
SELECT count(*) AS novas_vigencias, min(id_valor) AS menor_id, max(id_valor) AS maior_id
FROM novas;

-- Conferência: dentro da transação já enxergamos o reajuste
SELECT count(*) AS cervejas_com_preco_vigente
FROM table_valor v JOIN table_bebidas b USING (id_bebida)
WHERE b.categoria = 'Cerveja' AND v.ativo AND v.data_vigencia_fim IS NULL
  AND v.data_vigencia_inicio = CURRENT_DATE;

ROLLBACK;   -- gestor reprovou

-- Depois do ROLLBACK, nada mudou (atomicidade)
SELECT count(*) AS vigencias_hoje_depois
FROM table_valor v JOIN table_bebidas b USING (id_bebida)
WHERE b.categoria = 'Cerveja' AND v.data_vigencia_inicio = CURRENT_DATE;


-- =========================================================
-- TRANSAÇÃO 4 - Variante 100% SQL (sem \gset): funciona em DBeaver/pgAdmin
--   Encadeia INSERT ... RETURNING em CTEs: o id_cliente gerado no primeiro
--   INSERT é usado direto no INSERT do pedido, e o pedido baixa o estoque,
--   tudo em UM comando dentro da transação.
-- =========================================================
\echo
\echo '=== TRANSACAO 4: cliente + pedido + baixa de estoque em CTE unica ==='

BEGIN;

WITH novo_cliente AS (
    INSERT INTO table_clientes (nome, tipo_pessoa, cpf_cnpj, telefone, cidade, estado)
    VALUES ('Maria Souza', 'Fisica', '98765432100', '11999998888', 'Santos', 'SP')
    RETURNING id_cliente
), preco AS (
    SELECT v.id_valor, v.id_bebida, v.preco_venda
    FROM table_valor v
    WHERE v.ativo AND v.data_vigencia_fim IS NULL
      AND v.id_bebida = (SELECT id_bebida FROM table_bebidas
                          WHERE ativo AND estoque_atual >= 100 ORDER BY id_bebida LIMIT 1)
), novo_pedido AS (
    INSERT INTO table_comercio (id_cliente, id_bebida, id_valor, quantidade, valor_total, forma_pagamento)
    SELECT c.id_cliente, p.id_bebida, p.id_valor, 6, 6 * p.preco_venda, 'Dinheiro'
    FROM novo_cliente c CROSS JOIN preco p
    RETURNING id_pedido, id_cliente, id_bebida, quantidade, valor_total
), baixa AS (
    UPDATE table_bebidas b
       SET estoque_atual = b.estoque_atual - np.quantidade
      FROM novo_pedido np
     WHERE b.id_bebida = np.id_bebida
    RETURNING b.id_bebida, b.estoque_atual
)
SELECT np.id_pedido, np.id_cliente, np.valor_total, bx.estoque_atual AS estoque_depois
FROM novo_pedido np JOIN baixa bx USING (id_bebida);

COMMIT;

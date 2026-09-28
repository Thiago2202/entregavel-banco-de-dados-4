-- =========================================================
-- 07_testes_acesso.sql - Prova prática das permissões
--
-- Executa como superusuário/dono e assume cada identidade com SET ROLE.
-- Linhas "ERROR: permission denied" são o resultado ESPERADO (acesso negado).
-- As operações permitidas rodam dentro de BEGIN...ROLLBACK para não
-- alterar os dados. (não use -v ON_ERROR_STOP=1 neste arquivo)
-- =========================================================

SET search_path TO express;

-- =========================================================
-- usr_analista (role_leitura)
-- =========================================================
SET ROLE usr_analista;
SELECT current_user AS identidade;

\echo '--- [OK esperado] consulta de relatorio sem dados pessoais'
SELECT c.cidade, count(*) AS pedidos, sum(p.valor_total) AS faturamento
FROM table_comercio p JOIN table_clientes c ON c.id_cliente = p.id_cliente
WHERE p.data_pedido >= now() - interval '30 days'
GROUP BY c.cidade ORDER BY faturamento DESC LIMIT 3;

\echo '--- [NEGADO esperado] ler CPF/CNPJ (coluna sensivel)'
SELECT cpf_cnpj FROM table_clientes LIMIT 1;

\echo '--- [NEGADO esperado] SELECT * inclui colunas sensiveis'
SELECT * FROM table_clientes LIMIT 1;

\echo '--- [NEGADO esperado] INSERT / UPDATE / DELETE'
INSERT INTO table_bebidas (nome, categoria) VALUES ('Teste', 'Teste');
UPDATE table_valor SET preco_venda = 0.01;
DELETE FROM table_comercio;

RESET ROLE;

-- =========================================================
-- usr_vendedor (role_operacao)
-- =========================================================
SET ROLE usr_vendedor;
SELECT current_user AS identidade;

\echo '--- [OK esperado] cadastra cliente, lanca pedido e baixa estoque (depois ROLLBACK)'
BEGIN;
INSERT INTO table_clientes (nome, tipo_pessoa, cpf_cnpj, cidade, estado)
VALUES ('Teste Vendedor', 'Fisica', '11122233344', 'Campinas', 'SP')
RETURNING id_cliente AS id_cliente_teste \gset
INSERT INTO table_comercio (id_cliente, id_bebida, id_valor, quantidade, valor_total, forma_pagamento)
SELECT :id_cliente_teste, id_bebida, id_valor, 2, 2 * preco_venda, 'Pix'
FROM table_valor WHERE ativo AND data_vigencia_fim IS NULL ORDER BY id_bebida LIMIT 1
RETURNING id_pedido, valor_total;
UPDATE table_bebidas SET estoque_atual = estoque_atual - 2 WHERE id_bebida = 1
RETURNING id_bebida, estoque_atual;
UPDATE table_comercio SET status_entrega = 'Em rota' WHERE id_pedido = 1 AND FALSE;  -- coluna permitida
ROLLBACK;

\echo '--- [NEGADO esperado] alterar preco'
UPDATE table_valor SET preco_venda = 0.01 WHERE id_valor = 1;

\echo '--- [NEGADO esperado] alterar CPF de cliente (coluna fora do UPDATE permitido)'
UPDATE table_clientes SET cpf_cnpj = '00000000000' WHERE id_cliente = 1;

\echo '--- [NEGADO esperado] alterar quantidade/valor de pedido ja lancado'
UPDATE table_comercio SET valor_total = 0 WHERE id_pedido = 1;

\echo '--- [NEGADO esperado] DELETE e TRUNCATE'
DELETE FROM table_comercio WHERE id_pedido = 1;
TRUNCATE table_comercio;

\echo '--- [NEGADO esperado] DDL (criar tabela / alterar estrutura)'
CREATE TABLE table_intrusa (id int);
ALTER TABLE table_bebidas ADD COLUMN x int;

RESET ROLE;

-- =========================================================
-- REVOKE / GRANT em ação: retirar e devolver permissão em tempo real
-- =========================================================
\echo
\echo '=== REVOKE de coluna: vendedor perde a baixa de estoque ==='
REVOKE UPDATE (estoque_atual) ON table_bebidas FROM role_operacao;

SET ROLE usr_vendedor;
UPDATE table_bebidas SET estoque_atual = estoque_atual - 1 WHERE id_bebida = 1;   -- agora negado
RESET ROLE;

\echo '=== GRANT: permissao devolvida ==='
GRANT UPDATE (estoque_atual) ON table_bebidas TO role_operacao;

SET ROLE usr_vendedor;
BEGIN;
UPDATE table_bebidas SET estoque_atual = estoque_atual - 1 WHERE id_bebida = 1 RETURNING id_bebida, estoque_atual;
ROLLBACK;
RESET ROLE;

\echo
\echo '=== REVOKE de role: usuario desligado da equipe de operacao ==='
REVOKE role_operacao FROM usr_vendedor;
SET ROLE usr_vendedor;
SELECT count(*) FROM express.table_comercio;   -- negado: sem role, sem acesso ao schema
RESET ROLE;
GRANT role_operacao TO usr_vendedor;       -- restaura

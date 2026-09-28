-- =========================================================
-- 06_controle_acesso.sql - Roles, usuários, GRANT e REVOKE
--
-- Princípio do menor privilégio: cada perfil recebe SOMENTE o que
-- precisa para o trabalho, e o padrão é "negado".
--
--   ROLES (grupos, NOLOGIN - não fazem login, só agrupam permissões)
--     role_leitura   -> consulta relatórios; NÃO vê dados pessoais de clientes
--     role_operacao  -> registra clientes/pedidos e baixa estoque; não mexe em preços
--
--   USUÁRIOS (LOGIN - herdam as permissões da role a que pertencem)
--     usr_analista   in role_leitura
--     usr_vendedor   in role_operacao
--
-- Quem executa este script (ex.: postgres) é o dono dos objetos/DBA.
-- Requer privilégio para CREATE ROLE. Re-executável.
-- =========================================================

-- ---------------------------------------------------------
-- 0. Limpeza para re-execução (roles são globais no cluster)
-- ---------------------------------------------------------
DO $$
DECLARE r text;
BEGIN
    FOREACH r IN ARRAY ARRAY['usr_analista', 'usr_vendedor', 'role_leitura', 'role_operacao'] LOOP
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('DROP OWNED BY %I', r);   -- remove GRANTs desta role neste banco
            EXECUTE format('DROP ROLE %I', r);
        END IF;
    END LOOP;
END $$;

-- ---------------------------------------------------------
-- 1. Criação das ROLES e dos USUÁRIOS
--    (troque as senhas de exemplo antes de usar fora de um ambiente de estudo)
-- ---------------------------------------------------------
CREATE ROLE role_leitura  NOLOGIN;
CREATE ROLE role_operacao NOLOGIN;

CREATE ROLE usr_analista LOGIN PASSWORD 'analista_troque_123' CONNECTION LIMIT 5;
CREATE ROLE usr_vendedor LOGIN PASSWORD 'vendedor_troque_123' CONNECTION LIMIT 20;

GRANT role_leitura  TO usr_analista;
GRANT role_operacao TO usr_vendedor;

-- Limite de segurança: consulta de relatório não pode monopolizar o servidor
ALTER ROLE usr_analista SET statement_timeout = '30s';

-- ---------------------------------------------------------
-- 2. Fechar o que vem aberto por padrão (REVOKE do pseudo-role PUBLIC)
-- ---------------------------------------------------------
DO $$
BEGIN
    EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database());
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO role_leitura, role_operacao', current_database());
END $$;

REVOKE CREATE ON SCHEMA public FROM PUBLIC;          -- ninguém cria objetos no schema public
REVOKE ALL ON SCHEMA express FROM PUBLIC;
REVOKE ALL ON ALL TABLES    IN SCHEMA express FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA express FROM PUBLIC;

-- ---------------------------------------------------------
-- 3. role_leitura (analista): somente SELECT, sem dados pessoais
--    cpf_cnpj, telefone, email, endereco, numero e cep ficam de fora
--    (colunas sensíveis - LGPD). Ainda dá para analisar por cidade/bairro.
-- ---------------------------------------------------------
GRANT USAGE ON SCHEMA express TO role_leitura;

GRANT SELECT ON express.table_bebidas, express.table_valor, express.table_comercio
    TO role_leitura;

GRANT SELECT (id_cliente, nome, tipo_pessoa, bairro, cidade, estado,
              ativo, data_cadastro, abastecido_mes)
    ON express.table_clientes TO role_leitura;

-- ---------------------------------------------------------
-- 4. role_operacao (vendedor): rotina de balcão/entrega
--    - lê tudo (precisa do cadastro completo para atender)
--    - cadastra e edita clientes, mas NÃO altera o documento (cpf_cnpj/tipo_pessoa)
--    - registra pedidos e só atualiza andamento (status/entrega/pagamento)
--    - só altera estoque_atual da bebida (baixa da venda)
--    - NÃO tem DELETE em nenhuma tabela e NÃO altera preços (table_valor)
-- ---------------------------------------------------------
GRANT USAGE ON SCHEMA express TO role_operacao;

GRANT SELECT ON ALL TABLES IN SCHEMA express TO role_operacao;

GRANT INSERT ON express.table_clientes TO role_operacao;
GRANT UPDATE (nome, telefone, email, endereco, numero, bairro, cidade, estado, cep,
              ativo, abastecido_mes)
    ON express.table_clientes TO role_operacao;

GRANT INSERT ON express.table_comercio TO role_operacao;
GRANT UPDATE (status_entrega, data_entrega, forma_pagamento)
    ON express.table_comercio TO role_operacao;

GRANT UPDATE (estoque_atual) ON express.table_bebidas TO role_operacao;

-- INSERT em coluna SERIAL exige USAGE na sequence correspondente
GRANT USAGE ON SEQUENCE express.table_clientes_id_cliente_seq,
                        express.table_comercio_id_pedido_seq
    TO role_operacao;

-- ---------------------------------------------------------
-- 5. REVOKE explícito: o vendedor NÃO pode apagar nada
--    (já é negado por padrão; o REVOKE documenta a intenção e protege
--    contra GRANTs amplos futuros, ex.: GRANT ALL ...)
-- ---------------------------------------------------------
REVOKE DELETE, TRUNCATE ON ALL TABLES IN SCHEMA express FROM role_operacao;

-- Tabelas criadas no futuro NÃO herdam acesso automaticamente (padrão negado):
-- cada nova tabela precisa de um GRANT explícito e consciente.

-- ---------------------------------------------------------
-- 6. Conferência: privilégios efetivos por role
-- ---------------------------------------------------------
SELECT grantee, table_name, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privilegios
FROM information_schema.role_table_grants
WHERE table_schema = 'express' AND grantee IN ('role_leitura', 'role_operacao')
GROUP BY grantee, table_name
ORDER BY grantee, table_name;

SELECT grantee, table_name, string_agg(column_name, ', ' ORDER BY column_name) AS colunas, privilege_type
FROM information_schema.column_privileges
WHERE table_schema = 'express' AND grantee IN ('role_leitura', 'role_operacao')
  AND privilege_type IN ('UPDATE')
GROUP BY grantee, table_name, privilege_type
ORDER BY grantee, table_name;

SELECT r.rolname AS usuario, m.rolname AS pertence_a_role
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.member
JOIN pg_roles m ON m.oid = am.roleid
WHERE r.rolname IN ('usr_analista', 'usr_vendedor');

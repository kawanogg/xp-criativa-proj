-- ============================================================
-- Schema e dados fictícios — Rede de Farmácias
-- LGPD: dados gerados artificialmente, sem dados reais
-- ============================================================

-- Extensão para UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ── Tabela de clientes ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS clientes (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nome        VARCHAR(150) NOT NULL,
    cpf         CHAR(11) NOT NULL UNIQUE,
    email       VARCHAR(200) NOT NULL,
    telefone    VARCHAR(20),
    data_nasc   DATE,
    genero      CHAR(1),
    endereco    TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ── Tabela de produtos (catálogo) ──────────────────────────
CREATE TABLE IF NOT EXISTS produtos (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nome            VARCHAR(200) NOT NULL,
    descricao       TEXT,
    principio_ativo VARCHAR(200),
    preco           NUMERIC(10,2) NOT NULL,
    estoque         INTEGER DEFAULT 0,
    requer_receita  BOOLEAN DEFAULT FALSE,
    categoria       VARCHAR(100),
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ── Tabela de prontuários (dados médicos sensíveis) ─────────
CREATE TABLE IF NOT EXISTS prontuarios (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cliente_id  UUID NOT NULL REFERENCES clientes(id) ON DELETE CASCADE,
    cid         VARCHAR(10),
    prescricao  TEXT,
    medico      VARCHAR(150),
    crm         VARCHAR(20),
    plano_saude VARCHAR(100),
    data_emissao DATE,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ── Tabela de pedidos ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS pedidos (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cliente_id  UUID NOT NULL REFERENCES clientes(id),
    total       NUMERIC(10,2) NOT NULL,
    status      VARCHAR(50) DEFAULT 'pendente',
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ── Tabela de itens do pedido ──────────────────────────────
CREATE TABLE IF NOT EXISTS itens_pedido (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pedido_id   UUID NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
    produto_id  UUID NOT NULL REFERENCES produtos(id),
    quantidade  INTEGER NOT NULL,
    preco_unit  NUMERIC(10,2) NOT NULL
);

-- ── Índices de performance e segurança ────────────────────
CREATE INDEX idx_clientes_cpf   ON clientes(cpf);
CREATE INDEX idx_clientes_email ON clientes(email);
CREATE INDEX idx_pedidos_cliente ON pedidos(cliente_id);
CREATE INDEX idx_prontuario_cliente ON prontuarios(cliente_id);

-- ============================================================
-- Dados fictícios de teste (CPFs e nomes gerados)
-- ============================================================

INSERT INTO clientes (nome, cpf, email, telefone, data_nasc, genero, endereco) VALUES
('Ana Paula Fictícia',    '12345678901', 'ana.ficticia@exemplo.com',    '(41) 99901-0001', '1985-03-12', 'F', 'Rua das Flores, 100, Curitiba-PR'),
('Carlos Inventado',     '23456789012', 'carlos.inv@exemplo.com',       '(41) 99901-0002', '1990-07-24', 'M', 'Av. Brasil, 250, Curitiba-PR'),
('Maria Gerada',         '34567890123', 'maria.gerada@exemplo.com',     '(41) 99901-0003', '1978-11-05', 'F', 'Rua XV, 88, Curitiba-PR'),
('João Sintético',       '45678901234', 'joao.sintetico@exemplo.com',   '(41) 99901-0004', '2000-01-30', 'M', 'Rua Almirante, 33, Curitiba-PR'),
('Fernanda Mockada',     '56789012345', 'fernanda.mock@exemplo.com',    '(41) 99901-0005', '1995-06-18', 'F', 'Rua Iguaçu, 77, Curitiba-PR');

INSERT INTO produtos (nome, descricao, principio_ativo, preco, estoque, requer_receita, categoria) VALUES
('Dipirona 500mg Cx 20 cáps', 'Analgésico e antitérmico',        'Dipirona Sódica',    12.90,  500, FALSE, 'Analgésico'),
('Amoxicilina 500mg Cx 21 cáps', 'Antibiótico de amplo espectro', 'Amoxicilina',       35.50,  200, TRUE,  'Antibiótico'),
('Losartana 50mg Cx 30 comp',    'Anti-hipertensivo',             'Losartana Potássica', 18.75, 350, TRUE,  'Cardiovascular'),
('Protetor Solar FPS50 100ml',   'Proteção solar facial',         'Avobenzona',          52.00, 150, FALSE, 'Cosmético'),
('Vitamina C 1g Efervescente Cx 10', 'Suplemento vitamínico',    'Ácido Ascórbico',    19.90,  400, FALSE, 'Suplemento');

INSERT INTO prontuarios (cliente_id, cid, prescricao, medico, crm, plano_saude, data_emissao)
SELECT c.id, 'J06.9', 'Amoxicilina 500mg 3x ao dia por 7 dias', 'Dr. Teste Fictício', '12345-PR', 'Unimed', '2026-08-01'
FROM clientes c WHERE c.cpf = '23456789012';

INSERT INTO prontuarios (cliente_id, cid, prescricao, medico, crm, plano_saude, data_emissao)
SELECT c.id, 'I10', 'Losartana 50mg 1x ao dia', 'Dra. Exemplo Gerada', '67890-PR', 'Bradesco Saúde', '2026-07-15'
FROM clientes c WHERE c.cpf = '12345678901';

INSERT INTO pedidos (cliente_id, total, status)
SELECT c.id, 12.90, 'concluido'
FROM clientes c WHERE c.cpf = '12345678901';

-- ── View de relatório anonimizado (sem CPF direto) ────────
CREATE VIEW v_relatorio_anonimizado AS
SELECT
    CONCAT(LEFT(nome, POSITION(' ' IN nome) - 1), ' ***') AS nome_parcial,
    CONCAT(LEFT(cpf, 3), '.***.***-**')                   AS cpf_mascarado,
    DATE_PART('year', AGE(data_nasc))                      AS faixa_etaria,
    genero,
    (SELECT COUNT(*) FROM pedidos p WHERE p.cliente_id = c.id) AS total_pedidos
FROM clientes c;

-- ── Usuário de leitura limitada para a aplicação ──────────
DO 
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_readonly') THEN
        CREATE ROLE app_readonly LOGIN PASSWORD 'AppReadOnly2026!';
    END IF;
END
;

GRANT SELECT ON v_relatorio_anonimizado TO app_readonly;
GRANT SELECT ON produtos TO app_readonly;
GRANT SELECT, INSERT, UPDATE ON pedidos TO app_readonly;
GRANT SELECT, INSERT ON itens_pedido TO app_readonly;

-- ── Usuário padrão de testes com privilégios mínimos ───────
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'teste') THEN
        CREATE ROLE teste LOGIN PASSWORD 'T35t3';
    END IF;
END
$$;

-- Privilégios mínimos para o usuário de sistema teste:
GRANT SELECT ON produtos TO teste;
GRANT SELECT ON v_relatorio_anonimizado TO teste;

-- Cliente padrão de testes para aplicações:
INSERT INTO clientes (nome, cpf, email, telefone, data_nasc, genero, endereco) VALUES
('Usuario Teste PUC', '99999999999', 'teste@pucparana.com', '(41) 99999-9999', '2000-01-01', 'M', 'Rua Imaculada Conceicao, 1155, Curitiba-PR')
ON CONFLICT (cpf) DO NOTHING;


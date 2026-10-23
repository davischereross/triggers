-- atividade 1

CREATE TABLE estoque (
    id SERIAL PRIMARY KEY,
    nome_item VARCHAR(100) NOT NULL,
    quantidade INT NOT NULL DEFAULT 0
);

CREATE OR REPLACE FUNCTION fn_valida_estoque_minimo()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.quantidade < 0 THEN
        RAISE EXCEPTION
            'O item "%" não pode ter estoque negativo. Quantidade: %',
            NEW.nome_item, NEW.quantidade;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_valida_estoque
BEFORE INSERT OR UPDATE ON estoque
FOR EACH ROW
EXECUTE FUNCTION fn_valida_estoque_minimo();

INSERT INTO estoque (nome_item, quantidade)
VALUES ('Teclado Mecânico', 10);

-- atvidade 2

CREATE TABLE contas (
    id SERIAL PRIMARY KEY,
    cliente VARCHAR(100) NOT NULL,
    saldo NUMERIC(10,2) NOT NULL DEFAULT 0.00
);

CREATE TABLE movimentacoes (
    id SERIAL PRIMARY KEY,
    conta_id INT NOT NULL REFERENCES contas(id),
    tipo CHAR(1) NOT NULL CHECK (tipo IN ('C', 'D')),
    valor NUMERIC(10,2) NOT NULL CHECK (valor > 0),
    data_movimentacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION fn_atualiza_saldo_conta()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.tipo = 'C' THEN
        UPDATE contas
        SET saldo = saldo + NEW.valor
        WHERE id = NEW.conta_id;
    ELSIF NEW.tipo = 'D' THEN
        UPDATE contas
        SET saldo = saldo - NEW.valor
        WHERE id = NEW.conta_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_atualiza_saldo
AFTER INSERT ON movimentacoes
FOR EACH ROW
EXECUTE FUNCTION fn_atualiza_saldo_conta();

INSERT INTO contas (cliente, saldo)
VALUES ('João Silva', 500.00);

INSERT INTO movimentacoes (conta_id, tipo, valor)
VALUES (1, 'D', 150.00);

SELECT * FROM contas;

-- atividade 3
CREATE TABLE funcionarios (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    cargo VARCHAR(50) NOT NULL,
    salario NUMERIC(10,2) NOT NULL
);

CREATE TABLE historico_carreira (
    id SERIAL PRIMARY KEY,
    funcionario_id INT NOT NULL REFERENCES funcionarios(id),
    cargo_antigo VARCHAR(50),
    cargo_novo VARCHAR(50),
    salario_antigo NUMERIC(10,2),
    salario_novo NUMERIC(10,2),
    data_alteracao TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION fn_log_alteracao_carreira()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.cargo IS DISTINCT FROM NEW.cargo
       OR OLD.salario IS DISTINCT FROM NEW.salario THEN

        INSERT INTO historico_carreira (
            funcionario_id,
            cargo_antigo,
            cargo_novo,
            salario_antigo,
            salario_novo
        )
        VALUES (
            OLD.id,
            OLD.cargo,
            NEW.cargo,
            OLD.salario,
            NEW.salario
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_log_carreira
AFTER UPDATE ON funcionarios
FOR EACH ROW
EXECUTE FUNCTION fn_log_alteracao_carreira();

INSERT INTO funcionarios (nome, cargo, salario)
VALUES ('Maria Santos', 'Desenvolvedora Jr', 3500.00);

UPDATE funcionarios
SET cargo = 'Desenvolvedora Pleno',
    salario = 5500.00
WHERE id = 1;

SELECT * FROM historico_carreira;

-- atividade 4
CREATE TABLE clientes (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL,
    ativo BOOLEAN DEFAULT TRUE
);

CREATE TABLE clientes_deletados_log (
    id SERIAL PRIMARY KEY,
    cliente_id INT,
    nome VARCHAR(100),
    email VARCHAR(100),
    data_remocao TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION fn_soft_delete_cliente()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO clientes_deletados_log (
        cliente_id, nome, email
    )
    VALUES (
        OLD.id, OLD.nome, OLD.email
    );

    UPDATE clientes
    SET ativo = FALSE
    WHERE id = OLD.id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_soft_delete_cliente
BEFORE DELETE ON clientes
FOR EACH ROW
EXECUTE FUNCTION fn_soft_delete_cliente();

INSERT INTO clientes (nome, email)
VALUES ('Arthur Melzi', 'arthur@email.com');

DELETE FROM clientes
WHERE id = 1;

SELECT * FROM clientes;

SELECT * FROM clientes_deletados_log;

-- atividade 5 
CREATE TABLE reservas (
    id SERIAL PRIMARY KEY,
    numero_quarto INT NOT NULL,
    data_checkin DATE NOT NULL,
    data_checkout DATE NOT NULL,
    valor_diaria NUMERIC(10,2) NOT NULL CHECK (valor_diaria > 0),
    valor_total NUMERIC(10,2)
);

CREATE OR REPLACE FUNCTION fn_processa_reserva()
RETURNS TRIGGER AS $$
DECLARE
    dias_estadia INT;
BEGIN
    IF NEW.data_checkout <= NEW.data_checkin THEN
        RAISE EXCEPTION
            'O check-out deve ser posterior ao check-in.';
    END IF;

    dias_estadia := NEW.data_checkout - NEW.data_checkin;

    NEW.valor_total := dias_estadia * NEW.valor_diaria;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_processa_reserva
BEFORE INSERT OR UPDATE ON reservas
FOR EACH ROW
EXECUTE FUNCTION fn_processa_reserva();

INSERT INTO reservas (
    numero_quarto, data_checkin, data_checkout, valor_diaria
)
VALUES (101, '2026-11-01', '2026-11-06', 200.00);

SELECT * FROM reservas;

-- atividade 6
CREATE TABLE pedidos (
    id SERIAL PRIMARY KEY,
    cliente VARCHAR(100) NOT NULL,
    valor_total NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    data_criacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE itens_pedido (
    id SERIAL PRIMARY KEY,
    pedido_id INT NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
    produto_nome VARCHAR(100) NOT NULL,
    quantidade INT NOT NULL CHECK (quantidade > 0),
    preco_unitario NUMERIC(10,2) NOT NULL CHECK (preco_unitario >= 0)
);

CREATE OR REPLACE FUNCTION fn_recalcula_total_pedido()
RETURNS TRIGGER AS $$
DECLARE
    v_pedido_id INT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_pedido_id := OLD.pedido_id;
    ELSE
        v_pedido_id := NEW.pedido_id;
    END IF;

    UPDATE pedidos
    SET valor_total = COALESCE((
        SELECT SUM(quantidade * preco_unitario)
        FROM itens_pedido
        WHERE pedido_id = v_pedido_id
    ), 0.00)
    WHERE id = v_pedido_id;

    IF TG_OP = 'UPDATE' AND OLD.pedido_id <> NEW.pedido_id THEN
        UPDATE pedidos
        SET valor_total = COALESCE((
            SELECT SUM(quantidade * preco_unitario)
            FROM itens_pedido
            WHERE pedido_id = OLD.pedido_id
        ), 0.00)
        WHERE id = OLD.pedido_id;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_atualiza_total_pedido
AFTER INSERT OR UPDATE OR DELETE ON itens_pedido
FOR EACH ROW
EXECUTE FUNCTION fn_recalcula_total_pedido();

INSERT INTO pedidos (cliente)
VALUES ('Ana Souza');

INSERT INTO itens_pedido
(pedido_id, produto_nome, quantidade, preco_unitario)
VALUES
(1, 'Mouse Gamer', 2, 150.00),
(1, 'Mousepad', 1, 50.00);

SELECT * FROM pedidos;

DELETE FROM itens_pedido WHERE id = 2;

SELECT * FROM pedidos;

-- atividade 7
CREATE TABLE produtos (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    estoque_atual INT NOT NULL DEFAULT 0
        CHECK (estoque_atual >= 0)
);

CREATE TABLE itens_venda (
    id SERIAL PRIMARY KEY,
    produto_id INT NOT NULL REFERENCES produtos(id),
    quantidade_vendida INT NOT NULL CHECK (quantidade_vendida > 0),
    data_venda TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION fn_processa_baixa_estoque()
RETURNS TRIGGER AS $$
DECLARE
    v_estoque_atual INT;
    v_nome_produto VARCHAR(100);
BEGIN
    SELECT estoque_atual, nome
    INTO v_estoque_atual, v_nome_produto
    FROM produtos
    WHERE id = NEW.produto_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Produto com ID % não encontrado.',
            NEW.produto_id;
    END IF;

    IF v_estoque_atual < NEW.quantidade_vendida THEN
        RAISE EXCEPTION
            'Estoque insuficiente para "%". Disponível: %, solicitado: %.',
            v_nome_produto, v_estoque_atual, NEW.quantidade_vendida;
    END IF;

    UPDATE produtos
    SET estoque_atual = estoque_atual - NEW.quantidade_vendida
    WHERE id = NEW.produto_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_baixa_estoque_venda
BEFORE INSERT ON itens_venda
FOR EACH ROW
EXECUTE FUNCTION fn_processa_baixa_estoque();

INSERT INTO produtos (nome, estoque_atual)
VALUES ('Monitor Ultrawide', 5);

INSERT INTO itens_venda (produto_id, quantidade_vendida)
VALUES (1, 2);

SELECT * FROM produtos;

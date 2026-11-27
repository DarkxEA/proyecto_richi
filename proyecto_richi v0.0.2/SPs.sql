USE Huerto360;

-- =====================================================================
-- PROCEDIMIENTOS ALMACENADOS SINCRONIZADOS
-- =====================================================================

DROP PROCEDURE IF EXISTS sp_registrar_cosecha_agricultor;

DROP PROCEDURE IF EXISTS sp_registrar_jornada;
DROP PROCEDURE IF EXISTS sp_iniciar_entrega;
DROP PROCEDURE IF EXISTS sp_confirmar_entrega;
DROP PROCEDURE IF EXISTS sp_reportar_entrega_fallida;

DELIMITER //

-- Cosecha Agricultor -> Guarda cosecha Y suma stock al catálogo del Cliente
CREATE PROCEDURE sp_registrar_cosecha_agricultor(
    IN p_usuario_id INT UNSIGNED,
    IN p_parcela_id INT UNSIGNED,
    IN p_kg         DECIMAL(10,2),
    IN p_fecha      DATE,
    IN p_notas      TEXT
)
BEGIN
    DECLARE v_cultivo VARCHAR(80);
    DECLARE v_siembra DATE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT cultivo, fecha_siembra INTO v_cultivo, v_siembra
    FROM parcelas
    WHERE id = p_parcela_id AND usuario_id = p_usuario_id;

    IF v_cultivo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La parcela no existe o no te pertenece.';
    END IF;

    IF p_kg <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cantidad debe ser mayor que cero.';
    END IF;

    IF p_fecha > CURDATE() OR p_fecha < v_siembra THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha debe estar entre la siembra y hoy.';
    END IF;

    INSERT INTO cosechas (usuario_id, parcela_id, cultivo, kg, fecha, notas)
    VALUES (p_usuario_id, p_parcela_id, v_cultivo, p_kg, p_fecha, NULLIF(TRIM(p_notas), ''));

    -- Sincronizar con el catálogo del Cliente (sumar kilos al producto)
    INSERT INTO productos (nombre, icono, precio, stock)
    VALUES (v_cultivo, '🌱', 2500, ROUND(p_kg))
    ON DUPLICATE KEY UPDATE stock = stock + ROUND(p_kg);

    COMMIT;
END //



-- Jornada Entrada / Salida del Jornalero
CREATE PROCEDURE sp_registrar_jornada(
    IN p_usuario_id INT UNSIGNED,
    IN p_tipo       VARCHAR(10)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF UPPER(p_tipo) = 'ENTRADA' THEN
        IF EXISTS (SELECT 1 FROM jornadas WHERE usuario_id = p_usuario_id AND DATE(inicio) = CURDATE()) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ya registraste tu entrada el día de hoy.';
        END IF;
        INSERT INTO jornadas (usuario_id, inicio) VALUES (p_usuario_id, NOW());
    ELSEIF UPPER(p_tipo) = 'SALIDA' THEN
        UPDATE jornadas
        SET fin = NOW()
        WHERE usuario_id = p_usuario_id AND DATE(inicio) = CURDATE() AND fin IS NULL;

        IF ROW_COUNT() = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No tienes una jornada abierta hoy.';
        END IF;
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Acción de jornada no válida.';
    END IF;

    COMMIT;
END //

-- Transportista inicia entrega -> Actualiza también el pedido del Cliente a 'En ruta'
CREATE PROCEDURE sp_iniciar_entrega(
    IN p_entrega_id       INT UNSIGNED,
    IN p_transportista_id INT UNSIGNED
)
BEGIN
    DECLARE v_pedido INT UNSIGNED;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT pedido_numero INTO v_pedido FROM entregas WHERE id = p_entrega_id FOR UPDATE;

    UPDATE entregas
    SET estado = 'En ruta',
        transportista_id = p_transportista_id
    WHERE id = p_entrega_id
      AND estado = 'Pendiente'
      AND (transportista_id IS NULL OR transportista_id = p_transportista_id);

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Esta entrega ya no está disponible.';
    END IF;

    IF v_pedido IS NOT NULL THEN
        UPDATE pedidos SET estado = 'En ruta' WHERE numero = v_pedido AND estado = 'Pendiente';
    END IF;

    COMMIT;
END //

-- Transportista confirma entrega -> Actualiza el pedido del Cliente a 'Entregada'
CREATE PROCEDURE sp_confirmar_entrega(
    IN p_entrega_id       INT UNSIGNED,
    IN p_transportista_id INT UNSIGNED
)
BEGIN
    DECLARE v_pedido INT UNSIGNED;
    DECLARE v_pendientes INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT pedido_numero INTO v_pedido FROM entregas WHERE id = p_entrega_id FOR UPDATE;

    UPDATE entregas
    SET estado = 'Entregada',
        entregada_en = NOW()
    WHERE id = p_entrega_id
      AND estado = 'En ruta'
      AND transportista_id = p_transportista_id;

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se pudo confirmar la entrega.';
    END IF;

    -- Si todas las entregas de ese pedido ya fueron entregadas, marcar pedido como Entregada
    IF v_pedido IS NOT NULL THEN
        SELECT COUNT(*) INTO v_pendientes
        FROM entregas
        WHERE pedido_numero = v_pedido AND estado <> 'Entregada';

        IF v_pendientes = 0 THEN
            UPDATE pedidos SET estado = 'Entregada' WHERE numero = v_pedido;
        END IF;
    END IF;

    COMMIT;
END //

-- Transportista reporta entrega fallida -> Actualiza el pedido del Cliente
CREATE PROCEDURE sp_reportar_entrega_fallida(
    IN p_entrega_id       INT UNSIGNED,
    IN p_transportista_id INT UNSIGNED,
    IN p_nota             TEXT
)
BEGIN
    DECLARE v_pedido INT UNSIGNED;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF TRIM(COALESCE(p_nota, '')) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Debes indicar el motivo.';
    END IF;

    SELECT pedido_numero INTO v_pedido FROM entregas WHERE id = p_entrega_id FOR UPDATE;

    UPDATE entregas
    SET estado = 'No entregada',
        nota = TRIM(p_nota),
        entregada_en = NOW()
    WHERE id = p_entrega_id
      AND estado = 'En ruta'
      AND transportista_id = p_transportista_id;

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se pudo actualizar la entrega.';
    END IF;

    IF v_pedido IS NOT NULL THEN
        UPDATE pedidos SET estado = 'No entregada' WHERE numero = v_pedido;
    END IF;

    COMMIT;
END //

DELIMITER ;
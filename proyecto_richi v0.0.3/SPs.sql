-- =====================================================================
-- Huerto360 v0.0.3 · Colección Maestra Unificada de Procedimientos Almacenados
-- Contiene los 13 Procedimientos Almacenados con control transaccional,
-- validaciones de reglas de negocio y manejo de excepciones (SIGNAL SQLSTATE).
-- =====================================================================

USE Huerto360;

DROP PROCEDURE IF EXISTS sp_guardar_parcela;
DROP PROCEDURE IF EXISTS sp_registrar_cosecha_agricultor;
DROP PROCEDURE IF EXISTS sp_registrar_cosecha_jornalero;
DROP PROCEDURE IF EXISTS sp_registrar_jornada;
DROP PROCEDURE IF EXISTS sp_gestionar_tarea_jornalero;
DROP PROCEDURE IF EXISTS sp_crear_reporte_incidencia;
DROP PROCEDURE IF EXISTS sp_agregar_carrito;
DROP PROCEDURE IF EXISTS sp_modificar_carrito;
DROP PROCEDURE IF EXISTS sp_procesar_pedido;
DROP PROCEDURE IF EXISTS sp_cancelar_pedido;
DROP PROCEDURE IF EXISTS sp_iniciar_entrega;
DROP PROCEDURE IF EXISTS sp_confirmar_entrega;
DROP PROCEDURE IF EXISTS sp_reportar_entrega_fallida;

DELIMITER //

-- ---------------------------------------------------------------------
-- 1. Guardar o actualizar parcela (Agricultor)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_guardar_parcela(
    IN p_parcela_id  INT UNSIGNED,
    IN p_usuario_id  INT UNSIGNED,
    IN p_nombre      VARCHAR(100),
    IN p_cultivo     VARCHAR(80),
    IN p_area_m2     DECIMAL(10,2),
    IN p_siembra     DATE,
    IN p_etapa       VARCHAR(20)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF p_area_m2 <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La superficie debe ser mayor que cero.';
    END IF;

    IF p_siembra > CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de siembra no puede ser futura.';
    END IF;

    IF p_parcela_id IS NOT NULL AND p_parcela_id > 0 THEN
        IF NOT EXISTS (SELECT 1 FROM parcelas WHERE id = p_parcela_id AND usuario_id = p_usuario_id) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La parcela no existe o no te pertenece.';
        END IF;

        UPDATE parcelas
        SET nombre = p_nombre,
            cultivo = p_cultivo,
            area_m2 = p_area_m2,
            fecha_siembra = p_siembra,
            etapa = p_etapa
        WHERE id = p_parcela_id AND usuario_id = p_usuario_id;
    ELSE
        INSERT INTO parcelas (usuario_id, nombre, cultivo, area_m2, fecha_siembra, etapa)
        VALUES (p_usuario_id, p_nombre, p_cultivo, p_area_m2, p_siembra, p_etapa);
    END IF;

    COMMIT;
END //

-- ---------------------------------------------------------------------
-- 2. Registrar cosecha del Agricultor -> suma stock al catálogo Cliente
-- ---------------------------------------------------------------------
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

    INSERT INTO productos (nombre, icono, precio, stock)
    VALUES (v_cultivo, '🌱', 2500, ROUND(p_kg))
    ON DUPLICATE KEY UPDATE stock = stock + ROUND(p_kg);

    COMMIT;
END //

-- ---------------------------------------------------------------------
-- 3. Registrar cosecha del Jornalero (solo en jornada activa)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_registrar_cosecha_jornalero(
    IN p_usuario_id INT UNSIGNED,
    IN p_cultivo    VARCHAR(80),
    IN p_zona       VARCHAR(50),
    IN p_kg         DECIMAL(10,2),
    IN p_fecha      DATE
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF NOT EXISTS (
        SELECT 1 FROM jornadas
        WHERE usuario_id = p_usuario_id AND DATE(inicio) = CURDATE() AND fin IS NULL
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Debes tener una jornada activa para registrar cosechas.';
    END IF;

    IF TRIM(COALESCE(p_cultivo, '')) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Selecciona un cultivo.';
    END IF;

    IF p_kg <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cantidad debe ser mayor que cero.';
    END IF;

    IF p_fecha > CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha no puede ser futura.';
    END IF;

    INSERT INTO cosechas (usuario_id, cultivo, zona, kg, fecha)
    VALUES (p_usuario_id, TRIM(p_cultivo), p_zona, p_kg, p_fecha);

    INSERT INTO productos (nombre, icono, precio, stock)
    VALUES (TRIM(p_cultivo), '🌱', 2500, ROUND(p_kg))
    ON DUPLICATE KEY UPDATE stock = stock + ROUND(p_kg);

    COMMIT;
END //

-- ---------------------------------------------------------------------
-- 4. Registrar Entrada / Salida de Jornada (Jornalero)
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- 5. Gestionar tareas del Jornalero (solo en jornada activa)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_gestionar_tarea_jornalero(
    IN p_tarea_id   INT UNSIGNED,
    IN p_usuario_id INT UNSIGNED,
    IN p_accion     VARCHAR(15)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF NOT EXISTS (
        SELECT 1 FROM jornadas
        WHERE usuario_id = p_usuario_id AND DATE(inicio) = CURDATE() AND fin IS NULL
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo puedes gestionar tareas durante tu jornada activa.';
    END IF;

    IF UPPER(p_accion) = 'INICIAR' THEN
        UPDATE tareas_jornalero
        SET estado = 'En proceso', usuario_id = p_usuario_id
        WHERE id = p_tarea_id
          AND estado = 'Pendiente'
          AND (usuario_id IS NULL OR usuario_id = p_usuario_id);

        IF ROW_COUNT() = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La tarea no está disponible para iniciar.';
        END IF;

    ELSEIF UPPER(p_accion) = 'COMPLETAR' THEN
        UPDATE tareas_jornalero
        SET estado = 'Completada', usuario_id = p_usuario_id
        WHERE id = p_tarea_id
          AND estado <> 'Completada'
          AND (usuario_id IS NULL OR usuario_id = p_usuario_id);

        IF ROW_COUNT() = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se pudo completar la tarea.';
        END IF;

        UPDATE tareas_huerto SET hecha = 1 WHERE tarea_jornalero_id = p_tarea_id;
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Acción de tarea no válida.';
    END IF;

    COMMIT;
END //

-- ---------------------------------------------------------------------
-- 6. Crear reporte de incidencia en campo (Jornalero)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_crear_reporte_incidencia(
    IN p_usuario_id  INT UNSIGNED,
    IN p_tipo        VARCHAR(50),
    IN p_zona        VARCHAR(50),
    IN p_descripcion TEXT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF NOT EXISTS (
        SELECT 1 FROM jornadas
        WHERE usuario_id = p_usuario_id AND DATE(inicio) = CURDATE() AND fin IS NULL
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Debes tener una jornada activa para reportar incidencias.';
    END IF;

    IF TRIM(COALESCE(p_descripcion, '')) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Marca al menos un hallazgo para el reporte.';
    END IF;

    INSERT INTO reportes (usuario_id, tipo, zona, descripcion, fecha)
    VALUES (p_usuario_id, p_tipo, p_zona, TRIM(p_descripcion), CURDATE());

    COMMIT;
END //

-- ---------------------------------------------------------------------
-- 7. Agregar producto al carrito del Cliente
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_agregar_carrito(
    IN p_usuario_id  INT UNSIGNED,
    IN p_producto_id INT UNSIGNED
)
BEGIN
    DECLARE v_stock INT DEFAULT 0;
    DECLARE v_actual INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT stock INTO v_stock
    FROM productos
    WHERE id = p_producto_id
    FOR UPDATE;

    IF v_stock IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El producto seleccionado no existe.';
    END IF;

    SELECT COALESCE(cantidad, 0) INTO v_actual
    FROM carrito_items
    WHERE usuario_id = p_usuario_id AND producto_id = p_producto_id;

    IF v_actual >= v_stock THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No hay más cantidad disponible de este producto.';
    END IF;

    INSERT INTO carrito_items (usuario_id, producto_id, cantidad)
    VALUES (p_usuario_id, p_producto_id, 1)
    ON DUPLICATE KEY UPDATE cantidad = cantidad + 1;

    COMMIT;
END //

-- ---------------------------------------------------------------------
-- 8. Modificar ítem del carrito (RESTAR / QUITAR)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_modificar_carrito(
    IN p_usuario_id  INT UNSIGNED,
    IN p_producto_id INT UNSIGNED,
    IN p_accion      VARCHAR(10)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF UPPER(p_accion) = 'RESTAR' THEN
        UPDATE carrito_items
        SET cantidad = cantidad - 1
        WHERE usuario_id = p_usuario_id AND producto_id = p_producto_id;

        DELETE FROM carrito_items
        WHERE usuario_id = p_usuario_id AND producto_id = p_producto_id AND cantidad <= 0;

    ELSEIF UPPER(p_accion) = 'QUITAR' THEN
        DELETE FROM carrito_items
        WHERE usuario_id = p_usuario_id AND producto_id = p_producto_id;

    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Acción sobre el carrito no válida.';
    END IF;

    COMMIT;
END //

-- ---------------------------------------------------------------------
-- 9. Procesar pedido del Cliente
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_procesar_pedido(
    IN  p_usuario_id  INT UNSIGNED,
    IN  p_nombre      VARCHAR(100),
    IN  p_telefono    VARCHAR(20),
    IN  p_direccion   TEXT,
    OUT p_pedido_num  INT UNSIGNED
)
BEGIN
    DECLARE v_total INT UNSIGNED DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF (SELECT COUNT(*) FROM carrito_items WHERE usuario_id = p_usuario_id) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tu carrito está vacío.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM carrito_items c
        JOIN productos p ON p.id = c.producto_id
        WHERE c.usuario_id = p_usuario_id AND c.cantidad > p.stock
        FOR UPDATE
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Revisa la disponibilidad de los productos.';
    END IF;

    SELECT SUM(c.cantidad * p.precio) INTO v_total
    FROM carrito_items c
    JOIN productos p ON p.id = c.producto_id
    WHERE c.usuario_id = p_usuario_id;

    INSERT INTO pedidos (usuario_id, cliente_nombre, telefono, direccion, total, estado, creado_en)
    VALUES (p_usuario_id, p_nombre, p_telefono, p_direccion, v_total, 'Pendiente', NOW());

    SET p_pedido_num = LAST_INSERT_ID();

    INSERT INTO pedido_items (pedido_numero, producto_id, nombre, precio, cantidad)
    SELECT p_pedido_num, c.producto_id, p.nombre, p.precio, c.cantidad
    FROM carrito_items c
    JOIN productos p ON p.id = c.producto_id
    WHERE c.usuario_id = p_usuario_id;

    INSERT INTO entregas (pedido_numero, cliente, direccion, cultivo, cantidad, fecha, estado)
    SELECT p_pedido_num, p_nombre, p_direccion, p.nombre, c.cantidad, CURDATE(), 'Pendiente'
    FROM carrito_items c
    JOIN productos p ON p.id = c.producto_id
    WHERE c.usuario_id = p_usuario_id;

    UPDATE productos p
    JOIN carrito_items c ON c.producto_id = p.id
    SET p.stock = p.stock - c.cantidad
    WHERE c.usuario_id = p_usuario_id;

    DELETE FROM carrito_items WHERE usuario_id = p_usuario_id;

    UPDATE usuarios
    SET nombre = p_nombre, telefono = p_telefono, direccion = p_direccion
    WHERE id = p_usuario_id;

    COMMIT;
END //

-- ---------------------------------------------------------------------
-- 10. Cancelar pedido pendiente (Cliente)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_cancelar_pedido(
    IN p_pedido_numero INT UNSIGNED,
    IN p_usuario_id    INT UNSIGNED
)
BEGIN
    DECLARE v_estado VARCHAR(20);
    DECLARE v_en_camino INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT estado INTO v_estado
    FROM pedidos
    WHERE numero = p_pedido_numero AND usuario_id = p_usuario_id
    FOR UPDATE;

    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El pedido no existe.';
    END IF;

    IF v_estado <> 'Pendiente' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo se pueden cancelar pedidos pendientes.';
    END IF;

    SELECT COUNT(*) INTO v_en_camino
    FROM entregas
    WHERE pedido_numero = p_pedido_numero AND estado <> 'Pendiente';

    IF v_en_camino > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El pedido ya va en camino y no se puede cancelar.';
    END IF;

    UPDATE productos p
    JOIN pedido_items i ON i.producto_id = p.id
    SET p.stock = p.stock + i.cantidad
    WHERE i.pedido_numero = p_pedido_numero;

    DELETE FROM entregas WHERE pedido_numero = p_pedido_numero;

    UPDATE pedidos 
    SET estado = 'Cancelado' 
    WHERE numero = p_pedido_numero;

    COMMIT;
END //

-- ---------------------------------------------------------------------
-- 11. Iniciar entrega (Transportista) -> sincroniza Pedido a 'En ruta'
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- 12. Confirmar entrega realizada (Transportista) -> sincroniza Pedido a 'Entregada'
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- 13. Reportar entrega fallida (Transportista) -> sincroniza Pedido a 'No entregada'
-- ---------------------------------------------------------------------
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

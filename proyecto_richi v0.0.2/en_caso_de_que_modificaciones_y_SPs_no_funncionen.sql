USE Huerto360;

-- 1. Agregar el rol 'admin' a la tabla de usuarios
ALTER TABLE usuarios 
  MODIFY COLUMN rol ENUM('admin','agricultor','cliente','jornalero','trasportista') NOT NULL;

-- 2. Crear la cuenta de Administrador (Correo: admin@huerto360.com | Clave: admin123)
INSERT INTO usuarios (nombre, rol, correo, contrasena)
VALUES (
  'Administrador Huerto360',
  'admin',
  'admin@huerto360.com',
  '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi'
)
ON DUPLICATE KEY UPDATE 
  rol = 'admin';

-- 3. Ampliar estados de pedidos para reflejar el seguimiento del Transportista al Cliente
ALTER TABLE pedidos 
  MODIFY COLUMN estado ENUM('Pendiente','En ruta','Entregada','No entregada','Cancelado') NOT NULL DEFAULT 'Pendiente';

-- 4. Conectar tareas del Administrador (tareas_huerto) con las del Jornalero (tareas_jornalero)
ALTER TABLE tareas_huerto 
  ADD COLUMN zona ENUM('Invernadero','Exterior','Huerto norte') NOT NULL DEFAULT 'Invernadero',
  ADD COLUMN tarea_jornalero_id INT UNSIGNED NULL;

-- =====================================================================
-- PROCEDIMIENTOS ALMACENADOS PARA MYSQL / MARIADB
-- =====================================================================

DROP PROCEDURE IF EXISTS sp_guardar_parcela;
DROP PROCEDURE IF EXISTS sp_registrar_cosecha_agricultor;
DROP PROCEDURE IF EXISTS sp_registrar_cosecha_jornalero;
DROP PROCEDURE IF EXISTS sp_registrar_jornada;
DROP PROCEDURE IF EXISTS sp_procesar_pedido;
DROP PROCEDURE IF EXISTS sp_iniciar_entrega;
DROP PROCEDURE IF EXISTS sp_confirmar_entrega;
DROP PROCEDURE IF EXISTS sp_reportar_entrega_fallida;

DELIMITER //

-- 1. Guardar o actualizar parcela (con validaciones completas)
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

    IF TRIM(COALESCE(p_nombre, '')) = '' OR TRIM(COALESCE(p_cultivo, '')) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El nombre de la parcela y el cultivo son obligatorios.';
    END IF;

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
        SET nombre = TRIM(p_nombre),
            cultivo = TRIM(p_cultivo),
            area_m2 = p_area_m2,
            fecha_siembra = p_siembra,
            etapa = p_etapa
        WHERE id = p_parcela_id AND usuario_id = p_usuario_id;
    ELSE
        INSERT INTO parcelas (usuario_id, nombre, cultivo, area_m2, fecha_siembra, etapa)
        VALUES (p_usuario_id, TRIM(p_nombre), TRIM(p_cultivo), p_area_m2, p_siembra, p_etapa);
    END IF;

    COMMIT;
END //

-- 2. Cosecha Agricultor -> Registra cosecha y suma kilos al stock del Cliente
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

    -- Sincronizar con el catálogo del Cliente
    INSERT INTO productos (nombre, icono, precio, stock)
    VALUES (v_cultivo, '🌱', 2500, ROUND(p_kg))
    ON DUPLICATE KEY UPDATE stock = stock + ROUND(p_kg);

    COMMIT;
END //

-- 3. Cosecha Jornalero -> Registra cosecha y suma kilos al stock del Cliente
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

    -- Sincronizar con el catálogo del Cliente
    INSERT INTO productos (nombre, icono, precio, stock)
    VALUES (TRIM(p_cultivo), '🌱', 2500, ROUND(p_kg))
    ON DUPLICATE KEY UPDATE stock = stock + ROUND(p_kg);

    COMMIT;
END //

-- 4. Entrada y salida de jornada del Jornalero
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

-- 5. Procesar pedido del Cliente -> Descuenta stock y crea entregas para Transportistas
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

    IF TRIM(COALESCE(p_nombre, '')) = '' OR TRIM(COALESCE(p_telefono, '')) = '' OR TRIM(COALESCE(p_direccion, '')) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Completa tu nombre, teléfono y dirección.';
    END IF;

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
    VALUES (p_usuario_id, TRIM(p_nombre), TRIM(p_telefono), TRIM(p_direccion), v_total, 'Pendiente', NOW());

    SET p_pedido_num = LAST_INSERT_ID();

    INSERT INTO pedido_items (pedido_numero, producto_id, nombre, precio, cantidad)
    SELECT p_pedido_num, c.producto_id, p.nombre, p.precio, c.cantidad
    FROM carrito_items c
    JOIN productos p ON p.id = c.producto_id
    WHERE c.usuario_id = p_usuario_id;

    INSERT INTO entregas (pedido_numero, cliente, direccion, cultivo, cantidad, fecha, estado)
    SELECT p_pedido_num, TRIM(p_nombre), TRIM(p_direccion), p.nombre, c.cantidad, CURDATE(), 'Pendiente'
    FROM carrito_items c
    JOIN productos p ON p.id = c.producto_id
    WHERE c.usuario_id = p_usuario_id;

    UPDATE productos p
    JOIN carrito_items c ON c.producto_id = p.id
    SET p.stock = p.stock - c.cantidad
    WHERE c.usuario_id = p_usuario_id;

    DELETE FROM carrito_items WHERE usuario_id = p_usuario_id;

    UPDATE usuarios
    SET nombre = TRIM(p_nombre), telefono = TRIM(p_telefono), direccion = TRIM(p_direccion)
    WHERE id = p_usuario_id;

    COMMIT;
END //

-- 6. Transportista inicia ruta -> Cambia entrega y pedido del Cliente a 'En ruta'
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

-- 7. Transportista confirma entrega -> Marca pedido del Cliente como 'Entregada'
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

-- 8. Transportista reporta entrega fallida -> Actualiza pedido del Cliente
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
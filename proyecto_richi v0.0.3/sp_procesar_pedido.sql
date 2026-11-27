USE Huerto360;

DROP PROCEDURE IF EXISTS sp_procesar_pedido;

DELIMITER //

CREATE PROCEDURE sp_procesar_pedido(
    IN  p_usuario_id  INT UNSIGNED,
    IN  p_nombre      VARCHAR(100),
    IN  p_telefono    VARCHAR(20),
    IN  p_direccion   TEXT,
    OUT p_pedido_num  INT UNSIGNED
)
proc_main: BEGIN
    DECLARE v_total INT UNSIGNED DEFAULT 0;

    -- Manejo de excepciones: si ocurre cualquier fallo, revierte la transacción
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- 1. Validar que el carrito no esté vacío
    IF (SELECT COUNT(*) FROM carrito_items WHERE usuario_id = p_usuario_id) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tu carrito está vacío.';
    END IF;

    -- 2. Validar disponibilidad de stock suficiente para todos los artículos
    IF EXISTS (
        SELECT 1
        FROM carrito_items c
        JOIN productos p ON p.id = c.producto_id
        WHERE c.usuario_id = p_usuario_id AND c.cantidad > p.stock
        FOR UPDATE
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Revisa la disponibilidad de los productos.';
    END IF;

    -- 3. Calcular el total del pedido en centavos
    SELECT SUM(c.cantidad * p.precio) INTO v_total
    FROM carrito_items c
    JOIN productos p ON p.id = c.producto_id
    WHERE c.usuario_id = p_usuario_id;

    -- 4. Crear el encabezado del pedido
    INSERT INTO pedidos (usuario_id, cliente_nombre, telefono, direccion, total, estado, creado_en)
    VALUES (p_usuario_id, p_nombre, p_telefono, p_direccion, v_total, 'Pendiente', NOW());

    SET p_pedido_num = LAST_INSERT_ID();

    -- 5. Insertar el detalle de los productos comprados
    INSERT INTO pedido_items (pedido_numero, producto_id, nombre, precio, cantidad)
    SELECT p_pedido_num, c.producto_id, p.nombre, p.precio, c.cantidad
    FROM carrito_items c
    JOIN productos p ON p.id = c.producto_id
    WHERE c.usuario_id = p_usuario_id;

    -- 6. Crear las órdenes de entrega correspondientes para los transportistas
    INSERT INTO entregas (pedido_numero, cliente, direccion, cultivo, cantidad, fecha, estado)
    SELECT p_pedido_num, p_nombre, p_direccion, p.nombre, c.cantidad, CURDATE(), 'Pendiente'
    FROM carrito_items c
    JOIN productos p ON p.id = c.producto_id
    WHERE c.usuario_id = p_usuario_id;

    -- 7. Descontar las cantidades del inventario
    UPDATE productos p
    JOIN carrito_items c ON c.producto_id = p.id
    SET p.stock = p.stock - c.cantidad
    WHERE c.usuario_id = p_usuario_id;

    -- 8. Vaciar el carrito de compras y actualizar el perfil del cliente
    DELETE FROM carrito_items WHERE usuario_id = p_usuario_id;

    UPDATE usuarios
    SET nombre = p_nombre, telefono = p_telefono, direccion = p_direccion
    WHERE id = p_usuario_id;

    COMMIT;
END //

DELIMITER ;
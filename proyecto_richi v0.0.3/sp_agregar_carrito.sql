USE Huerto360;

DELIMITER //

CREATE PROCEDURE sp_agregar_carrito(
    IN p_usuario_id  INT UNSIGNED,
    IN p_producto_id INT UNSIGNED
)
proc_main: BEGIN
    DECLARE v_stock INT DEFAULT 0;
    DECLARE v_actual INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Validar existencia del producto y bloquear fila para lectura consistente
    SELECT stock INTO v_stock
    FROM productos
    WHERE id = p_producto_id
    FOR UPDATE;

    IF v_stock IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El producto seleccionado no existe.';
    END IF;

    -- Obtener la cantidad actual en el carrito del cliente
    SELECT COALESCE(cantidad, 0) INTO v_actual
    FROM carrito_items
    WHERE usuario_id = p_usuario_id AND producto_id = p_producto_id;

    -- Validar disponibilidad de stock
    IF v_actual >= v_stock THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No hay más cantidad disponible de este producto.';
    END IF;

    -- Insertar primer ítem o incrementar la cantidad existente
    INSERT INTO carrito_items (usuario_id, producto_id, cantidad)
    VALUES (p_usuario_id, p_producto_id, 1)
    ON DUPLICATE KEY UPDATE cantidad = cantidad + 1;

    COMMIT;
END //

DELIMITER ;
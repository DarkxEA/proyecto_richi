USE Huerto360;

DROP PROCEDURE IF EXISTS sp_cancelar_pedido;

DELIMITER //

CREATE PROCEDURE sp_cancelar_pedido(
    IN p_pedido_numero INT UNSIGNED,
    IN p_usuario_id    INT UNSIGNED
)
proc_main: BEGIN
    DECLARE v_estado VARCHAR(20);
    DECLARE v_en_camino INT DEFAULT 0;

    -- Si ocurre cualquier error inesperado, revierte los cambios
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- 1. Validar que el pedido exista y pertenezca al usuario
    SELECT estado INTO v_estado
    FROM pedidos
    WHERE numero = p_pedido_numero AND usuario_id = p_usuario_id
    FOR UPDATE;

    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El pedido no existe.';
    END IF;

    -- 2. Validar que el pedido se encuentre en estado 'Pendiente'
    IF v_estado <> 'Pendiente' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo se pueden cancelar pedidos pendientes.';
    END IF;

    -- 3. Verificar que ninguna entrega haya iniciado ruta o finalizado
    SELECT COUNT(*) INTO v_en_camino
    FROM entregas
    WHERE pedido_numero = p_pedido_numero AND estado <> 'Pendiente';

    IF v_en_camino > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El pedido ya va en camino y no se puede cancelar.';
    END IF;

    -- 4. Reintegrar las cantidades al inventario de productos
    UPDATE productos p
    JOIN pedido_items i ON i.producto_id = p.id
    SET p.stock = p.stock + i.cantidad
    WHERE i.pedido_numero = p_pedido_numero;

    -- 5. Eliminar las órdenes de entrega generadas para los transportistas
    DELETE FROM entregas WHERE pedido_numero = p_pedido_numero;

    -- 6. Actualizar el estado del pedido a 'Cancelado'
    UPDATE pedidos 
    SET estado = 'Cancelado' 
    WHERE numero = p_pedido_numero;

    COMMIT;
END //

DELIMITER ;
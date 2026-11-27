DELIMITER //

CREATE PROCEDURE sp_modificar_carrito(
    IN p_usuario_id  INT UNSIGNED,
    IN p_producto_id INT UNSIGNED,
    IN p_accion      VARCHAR(10) -- 'RESTAR' o 'QUITAR'
)
proc_main: BEGIN
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

        -- Limpieza automática de renglones con cantidad cero o menor
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

DELIMITER ;
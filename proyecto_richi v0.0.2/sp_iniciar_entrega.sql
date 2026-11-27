USE Huerto360;

DROP PROCEDURE IF EXISTS sp_iniciar_entrega;

DELIMITER //

CREATE PROCEDURE sp_iniciar_entrega(
    IN p_entrega_id       INT UNSIGNED,
    IN p_transportista_id INT UNSIGNED
)
proc_main: BEGIN
    DECLARE v_filas_afectadas INT DEFAULT 0;

    -- Si ocurre algún error inesperado, deshacer la transacción
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Asignación y cambio de estado atómico
    UPDATE entregas
    SET estado = 'En ruta',
        transportista_id = p_transportista_id
    WHERE id = p_entrega_id
      AND estado = 'Pendiente'
      AND (transportista_id IS NULL OR transportista_id = p_transportista_id);

    SET v_filas_afectadas = ROW_COUNT();

    -- Si no se afectó ninguna fila, la entrega ya no está disponible o la tomó otro transportista
    IF v_filas_afectadas = 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Esta entrega ya no está disponible o fue asignada a otro transportista.';
    END IF;

    COMMIT;
END //

DELIMITER ;
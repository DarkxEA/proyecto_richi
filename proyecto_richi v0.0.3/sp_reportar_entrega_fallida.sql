-- 2. Procedimiento para reportar entrega no realizada
DROP PROCEDURE IF EXISTS sp_reportar_entrega_fallida;

DELIMITER //

CREATE PROCEDURE sp_reportar_entrega_fallida(
    IN p_entrega_id       INT UNSIGNED,
    IN p_transportista_id INT UNSIGNED,
    IN p_nota             TEXT
)
proc_main: BEGIN
    DECLARE v_filas INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF TRIM(COALESCE(p_nota, '')) = '' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Debes proporcionar el motivo por el cual no se entregó el paquete.';
    END IF;

    UPDATE entregas
    SET estado = 'No entregada',
        nota = p_nota,
        entregada_en = NOW()
    WHERE id = p_entrega_id
      AND estado = 'En ruta'
      AND transportista_id = p_transportista_id;

    SET v_filas = ROW_COUNT();

    IF v_filas = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se pudo actualizar el estado de la entrega.';
    END IF;

    COMMIT;
END //

DELIMITER ;
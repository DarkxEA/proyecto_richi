use huerto360;
DELIMITER //

create procedure sp_confirmar_entrega(
    IN p_entrega_id       INT UNSIGNED,
    IN p_transportista_id INT UNSIGNED
)
proc_main: BEGIN
    DECLARE v_filas INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    UPDATE entregas
    SET estado = 'Entregada',
        entregada_en = NOW()
    WHERE id = p_entrega_id
      AND estado = 'En ruta'
      AND transportista_id = p_transportista_id;

    SET v_filas = ROW_COUNT();

    IF v_filas = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se pudo confirmar la entrega. Verifica que la orden esté en ruta y te pertenezca.';
    END IF;

    COMMIT;
END //

DELIMITER ;
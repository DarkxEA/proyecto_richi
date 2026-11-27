-- 2. Procedimiento para registrar cosechas asociadas a parcelas
DROP PROCEDURE IF EXISTS sp_registrar_cosecha_agricultor;

DELIMITER //

CREATE PROCEDURE sp_registrar_cosecha_agricultor(
    IN p_usuario_id INT UNSIGNED,
    IN p_parcela_id INT UNSIGNED,
    IN p_kg         DECIMAL(10,2),
    IN p_fecha      DATE,
    IN p_notas      TEXT
)
proc_main: BEGIN
    DECLARE v_siembra DATE;
    DECLARE v_cultivo VARCHAR(80);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Verificar existencia y pertenencia de la parcela
    SELECT fecha_siembra, cultivo INTO v_siembra, v_cultivo
    FROM parcelas
    WHERE id = p_parcela_id AND usuario_id = p_usuario_id;

    IF v_siembra IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La parcela no existe o no te pertenece.';
    END IF;

    IF p_kg <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cantidad debe ser mayor que cero.';
    END IF;

    IF p_fecha > CURDATE() OR p_fecha < v_siembra THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de cosecha debe estar entre la fecha de siembra y el día de hoy.';
    END IF;

    INSERT INTO cosechas (usuario_id, parcela_id, cultivo, kg, fecha, notas)
    VALUES (p_usuario_id, p_parcela_id, v_cultivo, p_kg, p_fecha, IF(TRIM(p_notas) = '', NULL, p_notas));

    COMMIT;
END //

DELIMITER ;
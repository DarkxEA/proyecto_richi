USE Huerto360;

-- 1. Procedimiento para crear o actualizar parcelas
DROP PROCEDURE IF EXISTS sp_guardar_parcela;

DELIMITER //

CREATE PROCEDURE sp_guardar_parcela(
    IN p_parcela_id  INT UNSIGNED, -- NULL o 0 si es nueva parcela
    IN p_usuario_id  INT UNSIGNED,
    IN p_nombre      VARCHAR(100),
    IN p_cultivo     VARCHAR(80),
    IN p_area_m2     DECIMAL(10,2),
    IN p_siembra     DATE,
    IN p_etapa       VARCHAR(20)
)
proc_main: BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Validaciones
    IF p_area_m2 <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La superficie debe ser mayor que cero.';
    END IF;

    IF p_siembra > CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de siembra no puede ser futura.';
    END IF;

    -- Guardar o actualizar
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

DELIMITER ;
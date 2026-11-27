USE Huerto360;

DROP PROCEDURE IF EXISTS sp_crear_reporte_incidencia;

DELIMITER //


-- 3. Reportar incidencia del jornalero (solo en jornada activa)
CREATE PROCEDURE sp_crear_reporte_incidencia(
    IN p_usuario_id  INT UNSIGNED,
    IN p_tipo        VARCHAR(50),
    IN p_zona        VARCHAR(50),
    IN p_descripcion TEXT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF NOT EXISTS (
        SELECT 1 FROM jornadas
        WHERE usuario_id = p_usuario_id AND DATE(inicio) = CURDATE() AND fin IS NULL
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Debes tener una jornada activa para reportar incidencias.';
    END IF;

    IF TRIM(COALESCE(p_descripcion, '')) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Marca al menos un hallazgo para el reporte.';
    END IF;

    INSERT INTO reportes (usuario_id, tipo, zona, descripcion, fecha)
    VALUES (p_usuario_id, p_tipo, p_zona, TRIM(p_descripcion), CURDATE());

    COMMIT;
END //

DELIMITER ;
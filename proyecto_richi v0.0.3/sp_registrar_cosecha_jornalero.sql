USE Huerto360;

DELIMITER //

-- 2. Registrar cosecha del jornalero (solo en jornada activa)
CREATE PROCEDURE sp_registrar_cosecha_jornalero(
    IN p_usuario_id INT UNSIGNED,
    IN p_cultivo    VARCHAR(80),
    IN p_zona       VARCHAR(50),
    IN p_kg         DECIMAL(10,2),
    IN p_fecha      DATE
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
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Debes tener una jornada activa para registrar cosechas.';
    END IF;

    IF TRIM(COALESCE(p_cultivo, '')) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Selecciona un cultivo.';
    END IF;

    IF p_kg <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cantidad debe ser mayor que cero.';
    END IF;

    IF p_fecha > CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha no puede ser futura.';
    END IF;

    INSERT INTO cosechas (usuario_id, cultivo, zona, kg, fecha)
    VALUES (p_usuario_id, TRIM(p_cultivo), p_zona, p_kg, p_fecha);

    INSERT INTO productos (nombre, icono, precio, stock)
    VALUES (TRIM(p_cultivo), '🌱', 2500, ROUND(p_kg))
    ON DUPLICATE KEY UPDATE stock = stock + ROUND(p_kg);

    COMMIT;
END //

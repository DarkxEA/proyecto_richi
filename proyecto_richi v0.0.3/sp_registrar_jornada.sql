USE Huerto360;

DROP PROCEDURE IF EXISTS sp_registrar_jornada;

DELIMITER //

CREATE PROCEDURE sp_registrar_jornada(
    IN p_usuario_id INT UNSIGNED,
    IN p_accion     VARCHAR(10)
)
proc_main: BEGIN
    DECLARE v_filas INT DEFAULT 0;

    -- Manejo de excepciones: deshacer cambios ante cualquier error
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF UPPER(p_accion) = 'ENTRADA' THEN
        -- 1. Validar si el jornalero ya registró su entrada hoy
        IF EXISTS (
            SELECT 1 
            FROM jornadas 
            WHERE usuario_id = p_usuario_id 
              AND DATE(inicio) = CURDATE()
        ) THEN
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'Ya registraste tu entrada hoy.';
        END IF;

        -- 2. Insertar inicio de jornada
        INSERT INTO jornadas (usuario_id, inicio) 
        VALUES (p_usuario_id, NOW());

    ELSEIF UPPER(p_accion) = 'SALIDA' THEN
        -- 1. Registrar fecha/hora de salida en la jornada activa de hoy
        UPDATE jornadas 
        SET fin = NOW() 
        WHERE usuario_id = p_usuario_id 
          AND DATE(inicio) = CURDATE() 
          AND fin IS NULL;

        SET v_filas = ROW_COUNT();

        -- 2. Si no hay registros actualizados, no había entrada abierta hoy
        IF v_filas = 0 THEN
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'No hay una jornada abierta para registrar la salida.';
        END IF;

    ELSE
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Acción de jornada no válida.';
    END IF;

    COMMIT;
END //

DELIMITER ;
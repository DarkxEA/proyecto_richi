USE Huerto360;
DELIMITER //
-- 1. Iniciar o completar tarea (solo en jornada activa)
CREATE PROCEDURE sp_gestionar_tarea_jornalero(
    IN p_tarea_id   INT UNSIGNED,
    IN p_usuario_id INT UNSIGNED,
    IN p_accion     VARCHAR(15)
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
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo puedes gestionar tareas durante tu jornada activa.';
    END IF;

    IF UPPER(p_accion) = 'INICIAR' THEN
        UPDATE tareas_jornalero
        SET estado = 'En proceso', usuario_id = p_usuario_id
        WHERE id = p_tarea_id
          AND estado = 'Pendiente'
          AND (usuario_id IS NULL OR usuario_id = p_usuario_id);

        IF ROW_COUNT() = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La tarea no está disponible para iniciar.';
        END IF;

    ELSEIF UPPER(p_accion) = 'COMPLETAR' THEN
        UPDATE tareas_jornalero
        SET estado = 'Completada', usuario_id = p_usuario_id
        WHERE id = p_tarea_id
          AND estado <> 'Completada'
          AND (usuario_id IS NULL OR usuario_id = p_usuario_id);

        IF ROW_COUNT() = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se pudo completar la tarea.';
        END IF;

        -- Sincronizar con tareas del Administrador si está vinculada
        UPDATE tareas_huerto SET hecha = 1 WHERE tarea_jornalero_id = p_tarea_id;

    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Acción de tarea no válida.';
    END IF;

    COMMIT;
END //
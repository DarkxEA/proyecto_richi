<?php
// =====================================================================
// Huerto360 · Módulo Jornalero (Jornadas, Tareas, Cosechas e Incidencias)
// =====================================================================
require __DIR__ . '/_comun.php';

$d  = entrada();
$yo = requerir_usuario($conexion, ['jornalero']);
$uid = (int)$yo['id'];

const ZONAS = ['Invernadero', 'Exterior', 'Huerto norte'];

function jornada_activa(PDO $bd, int $uid): bool
{
    $st = $bd->prepare(
        'SELECT 1 FROM jornadas WHERE usuario_id = ? AND DATE(inicio) = ? AND fin IS NULL LIMIT 1'
    );
    $st->execute([$uid, hoy()]);
    return (bool)$st->fetchColumn();
}

function exigir_jornada_activa(PDO $bd, int $uid): void
{
    if (!jornada_activa($bd, $uid)) {
        fallar('Modo solo consulta: debes iniciar tu jornada (y no haberla finalizado) para realizar esta acción.');
    }
}

function estado(PDO $bd, int $uid): array
{
    $st = $bd->prepare('SELECT inicio, fin FROM jornadas WHERE usuario_id = ? ORDER BY id DESC LIMIT 1');
    $st->execute([$uid]);
    $j = $st->fetch();
    $shift = $j ? [
        'date'  => substr($j['inicio'], 0, 10),
        'start' => iso($j['inicio']),
        'end'   => iso($j['fin']),
    ] : null;

    $st = $bd->prepare(
        'SELECT id, nombre, zona, fecha, estado FROM tareas_jornalero
          WHERE usuario_id IS NULL OR usuario_id = ? ORDER BY id'
    );
    $st->execute([$uid]);
    $tasks = array_map(fn($r) => [
        'id'     => (int)$r['id'],
        'name'   => $r['nombre'],
        'zone'   => $r['zona'],
        'date'   => $r['fecha'],
        'status' => $r['estado'],
    ], $st->fetchAll());

    $st = $bd->prepare(
        'SELECT id, cultivo, zona, kg, fecha FROM cosechas
          WHERE usuario_id = ? AND parcela_id IS NULL ORDER BY id'
    );
    $st->execute([$uid]);
    $harvests = array_map(fn($r) => [
        'id'     => (int)$r['id'],
        'crop'   => $r['cultivo'],
        'zone'   => $r['zona'],
        'amount' => (float)$r['kg'],
        'date'   => $r['fecha'],
    ], $st->fetchAll());

    $st = $bd->prepare(
        'SELECT id, tipo, zona, descripcion, fecha FROM reportes WHERE usuario_id = ? ORDER BY id'
    );
    $st->execute([$uid]);
    $reports = array_map(fn($r) => [
        'id'          => (int)$r['id'],
        'type'        => $r['tipo'],
        'zone'        => $r['zona'],
        'description' => $r['descripcion'],
        'date'        => $r['fecha'],
    ], $st->fetchAll());

    return [
        'shift'       => $shift,
        'activeShift' => jornada_activa($bd, $uid),
        'tasks'       => $tasks,
        'harvests'    => $harvests,
        'reports'     => $reports,
    ];
}

switch ($d['accion'] ?? '') {
    case 'cargar':
        break;

    case 'entrada':
        try {
            $st = $conexion->prepare('CALL sp_registrar_jornada(?, \'ENTRADA\')');
            $st->execute([$uid]);
        } catch (PDOException $e) {
            fallar($e->getMessage());
        }
        break;

    case 'salida':
        try {
            $st = $conexion->prepare('CALL sp_registrar_jornada(?, \'SALIDA\')');
            $st->execute([$uid]);
        } catch (PDOException $e) {
            fallar($e->getMessage());
        }
        break;

    case 'iniciar_tarea':
        exigir_jornada_activa($conexion, $uid);
        $tid = (int)($d['id'] ?? 0);
        try {
            $st = $conexion->prepare('CALL sp_gestionar_tarea_jornalero(?, ?, \'INICIAR\')');
            $st->execute([$tid, $uid]);
        } catch (PDOException $e) {
            fallar($e->getMessage());
        }
        break;

    case 'completar_tarea':
        exigir_jornada_activa($conexion, $uid);
        $tid = (int)($d['id'] ?? 0);
        try {
            $st = $conexion->prepare('CALL sp_gestionar_tarea_jornalero(?, ?, \'COMPLETAR\')');
            $st->execute([$tid, $uid]);
        } catch (PDOException $e) {
            fallar($e->getMessage());
        }
        break;

    case 'guardar_cosecha':
        exigir_jornada_activa($conexion, $uid);
        $cultivo = texto($d['crop'] ?? '', 80, 'El cultivo');
        $zona    = opcion($d['zone'] ?? '', ZONAS, 'La zona');
        $kg      = numero_positivo($d['amount'] ?? 0, 'La cantidad');
        $fechaC  = fecha($d['date'] ?? '', 'La fecha');

        try {
            $st = $conexion->prepare('CALL sp_registrar_cosecha_jornalero(?, ?, ?, ?, ?)');
            $st->execute([$uid, $cultivo, $zona, $kg, $fechaC]);
        } catch (PDOException $e) {
            fallar($e->getMessage());
        }
        break;

    case 'reportar':
        exigir_jornada_activa($conexion, $uid);
        $tipo = opcion($d['type'] ?? '', ['Plaga', 'Falta de agua', 'Herramienta dañada', 'Otro'], 'El tipo de reporte');
        $zona = opcion($d['zone'] ?? '', ZONAS, 'La zona');
        $desc = texto($d['description'] ?? '', 1000, 'La descripción');

        try {
            $st = $conexion->prepare('CALL sp_crear_reporte_incidencia(?, ?, ?, ?)');
            $st->execute([$uid, $tipo, $zona, $desc]);
        } catch (PDOException $e) {
            fallar($e->getMessage());
        }
        break;

    default:
        fallar('Acción no válida.');
}

responder(['ok' => true, 'datos' => estado($conexion, $uid)]);

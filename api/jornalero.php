<?php
require __DIR__ . '/_comun.php';

$d  = entrada();
$yo = requerir_usuario($conexion, ['jornalero']);
$uid = (int)$yo['id'];

const ZONAS = ['Invernadero', 'Exterior', 'Huerto norte'];

/** Estado completo del jornalero, con la misma forma que usa Jornalero.html */
function estado(PDO $bd, int $uid): array
{
    // Última jornada registrada (la pantalla compara su fecha con la de hoy)
    $st = $bd->prepare('SELECT inicio, fin FROM jornadas WHERE usuario_id = ? ORDER BY id DESC LIMIT 1');
    $st->execute([$uid]);
    $j = $st->fetch();
    $shift = $j ? [
        'date'  => substr($j['inicio'], 0, 10),
        'start' => iso($j['inicio']),
        'end'   => iso($j['fin']),
    ] : null;

    // Tareas asignadas a este jornalero + tareas libres que cualquiera puede tomar
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

    return ['shift' => $shift, 'tasks' => $tasks, 'harvests' => $harvests, 'reports' => $reports];
}

switch ($d['accion'] ?? '') {
    case 'cargar':
        break;

    case 'entrada':
        $st = $conexion->prepare('SELECT 1 FROM jornadas WHERE usuario_id = ? AND DATE(inicio) = ?');
        $st->execute([$uid, hoy()]);
        if ($st->fetch()) {
            fallar('Ya registraste tu entrada hoy.');
        }
        $conexion->prepare('INSERT INTO jornadas (usuario_id, inicio) VALUES (?, ?)')
                 ->execute([$uid, ahora()]);
        break;

    case 'salida':
        $st = $conexion->prepare(
            'UPDATE jornadas SET fin = ? WHERE usuario_id = ? AND DATE(inicio) = ? AND fin IS NULL'
        );
        $st->execute([ahora(), $uid, hoy()]);
        if ($st->rowCount() === 0) {
            fallar('No hay una jornada abierta para registrar la salida.');
        }
        break;

    case 'iniciar_tarea':
        $st = $conexion->prepare(
            'UPDATE tareas_jornalero SET estado = \'En proceso\', usuario_id = ?
              WHERE id = ? AND estado = \'Pendiente\' AND (usuario_id IS NULL OR usuario_id = ?)'
        );
        $st->execute([$uid, (int)($d['id'] ?? 0), $uid]);
        break;

    case 'completar_tarea':
        $st = $conexion->prepare(
            'UPDATE tareas_jornalero SET estado = \'Completada\', usuario_id = ?
              WHERE id = ? AND estado <> \'Completada\' AND (usuario_id IS NULL OR usuario_id = ?)'
        );
        $st->execute([$uid, (int)($d['id'] ?? 0), $uid]);
        break;

    case 'guardar_cosecha':
        $cultivo = texto($d['crop'] ?? '', 80, 'El cultivo');
        $zona    = opcion($d['zone'] ?? '', ZONAS, 'La zona');
        $kg      = numero_positivo($d['amount'] ?? 0, 'La cantidad');
        $fechaC  = fecha($d['date'] ?? '', 'La fecha');
        $conexion->prepare(
            'INSERT INTO cosechas (usuario_id, cultivo, zona, kg, fecha) VALUES (?,?,?,?,?)'
        )->execute([$uid, $cultivo, $zona, $kg, $fechaC]);
        break;

    case 'reportar':
        $tipo = opcion($d['type'] ?? '', ['Plaga', 'Falta de agua', 'Herramienta dañada', 'Otro'], 'El tipo de reporte');
        $zona = opcion($d['zone'] ?? '', ZONAS, 'La zona');
        $desc = texto($d['description'] ?? '', 1000, 'La descripción');
        $conexion->prepare(
            'INSERT INTO reportes (usuario_id, tipo, zona, descripcion, fecha) VALUES (?,?,?,?,?)'
        )->execute([$uid, $tipo, $zona, $desc, hoy()]);
        break;

    default:
        fallar('Acción no válida.');
}

responder(['ok' => true, 'datos' => estado($conexion, $uid)]);

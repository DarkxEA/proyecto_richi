<?php
require __DIR__ . '/_comun.php';

$d  = entrada();
$yo = requerir_usuario($conexion, ['agricultor']);
$uid = (int)$yo['id'];

/** Estado completo del agricultor, con la misma forma que usa Agricultor.html */
function estado(PDO $bd, int $uid): array
{
    $st = $bd->prepare(
        'SELECT id, nombre, cultivo, area_m2, fecha_siembra, etapa
           FROM parcelas WHERE usuario_id = ? ORDER BY id'
    );
    $st->execute([$uid]);
    $plots = array_map(fn($r) => [
        'id'     => (string)$r['id'],
        'name'   => $r['nombre'],
        'crop'   => $r['cultivo'],
        'area'   => (float)$r['area_m2'],
        'sowing' => $r['fecha_siembra'],
        'stage'  => $r['etapa'],
    ], $st->fetchAll());

    $st = $bd->prepare(
        'SELECT t.id, t.parcela_id, t.nombre, t.fecha, t.completada
           FROM tareas_parcela t
           JOIN parcelas p ON p.id = t.parcela_id
          WHERE p.usuario_id = ? ORDER BY t.id'
    );
    $st->execute([$uid]);
    $tasks = array_map(fn($r) => [
        'id'     => (string)$r['id'],
        'plotId' => (string)$r['parcela_id'],
        'name'   => $r['nombre'],
        'date'   => $r['fecha'],
        'done'   => (bool)$r['completada'],
    ], $st->fetchAll());

    $st = $bd->prepare(
        'SELECT c.id, c.parcela_id, p.nombre AS parcela, COALESCE(c.cultivo, p.cultivo) AS cultivo,
                c.kg, c.fecha, c.notas
           FROM cosechas c
           JOIN parcelas p ON p.id = c.parcela_id
          WHERE p.usuario_id = ? ORDER BY c.id'
    );
    $st->execute([$uid]);
    $harvests = array_map(fn($r) => [
        'id'       => (string)$r['id'],
        'plotId'   => (string)$r['parcela_id'],
        'plotName' => $r['parcela'],
        'crop'     => $r['cultivo'],
        'kg'       => (float)$r['kg'],
        'date'     => $r['fecha'],
        'notes'    => $r['notas'] ?? '',
    ], $st->fetchAll());

    return ['plots' => $plots, 'tasks' => $tasks, 'harvests' => $harvests];
}

/** Devuelve la parcela solo si pertenece al agricultor con sesión. */
function parcela_propia(PDO $bd, int $uid, $id): array
{
    $st = $bd->prepare('SELECT * FROM parcelas WHERE id = ? AND usuario_id = ?');
    $st->execute([(int)$id, $uid]);
    $fila = $st->fetch();
    if (!$fila) {
        fallar('La parcela no existe.', 404);
    }
    return $fila;
}

switch ($d['accion'] ?? '') {
    case 'cargar':
        break;

    case 'guardar_parcela':
        $nombre = texto($d['name'] ?? '', 100, 'El nombre de la parcela');
        $cultivo = texto($d['crop'] ?? '', 80, 'El cultivo');
        $area = numero_positivo($d['area'] ?? 0, 'La superficie');
        $siembra = fecha($d['sowing'] ?? '', 'La fecha de siembra');
        if ($siembra > hoy()) {
            fallar('La fecha de siembra no puede ser futura.');
        }
        $etapa = opcion($d['stage'] ?? '', ['Siembra', 'Crecimiento', 'Floración', 'Cosecha', 'Finalizado'], 'La etapa');

        if (!empty($d['id'])) {
            parcela_propia($conexion, $uid, $d['id']);
            $conexion->prepare(
                'UPDATE parcelas SET nombre=?, cultivo=?, area_m2=?, fecha_siembra=?, etapa=?
                  WHERE id=? AND usuario_id=?'
            )->execute([$nombre, $cultivo, $area, $siembra, $etapa, (int)$d['id'], $uid]);
        } else {
            $conexion->prepare(
                'INSERT INTO parcelas (usuario_id, nombre, cultivo, area_m2, fecha_siembra, etapa)
                 VALUES (?,?,?,?,?,?)'
            )->execute([$uid, $nombre, $cultivo, $area, $siembra, $etapa]);
        }
        break;

    case 'guardar_tarea':
        $nombre = texto($d['name'] ?? '', 200, 'El nombre de la actividad');
        $fechaT = fecha($d['date'] ?? '', 'La fecha de la actividad');
        $parcela = parcela_propia($conexion, $uid, $d['plotId'] ?? 0);
        $conexion->prepare(
            'INSERT INTO tareas_parcela (parcela_id, nombre, fecha) VALUES (?,?,?)'
        )->execute([$parcela['id'], $nombre, $fechaT]);
        break;

    case 'alternar_tarea':
        $st = $conexion->prepare(
            'UPDATE tareas_parcela t JOIN parcelas p ON p.id = t.parcela_id
                SET t.completada = 1 - t.completada
              WHERE t.id = ? AND p.usuario_id = ?'
        );
        $st->execute([(int)($d['id'] ?? 0), $uid]);
        break;

    case 'eliminar_tarea':
        $st = $conexion->prepare(
            'DELETE t FROM tareas_parcela t JOIN parcelas p ON p.id = t.parcela_id
              WHERE t.id = ? AND p.usuario_id = ?'
        );
        $st->execute([(int)($d['id'] ?? 0), $uid]);
        break;

    case 'guardar_cosecha':
        $parcela = parcela_propia($conexion, $uid, $d['plotId'] ?? 0);
        $kg = numero_positivo($d['kg'] ?? 0, 'La cantidad');
        $fechaC = fecha($d['date'] ?? '', 'La fecha de cosecha');
        if ($fechaC > hoy() || $fechaC < $parcela['fecha_siembra']) {
            fallar('La fecha debe estar entre la siembra y hoy.');
        }
        $notas = texto_opcional($d['notes'] ?? '', 1000, 'Las observaciones');
        $conexion->prepare(
            'INSERT INTO cosechas (usuario_id, parcela_id, cultivo, kg, fecha, notas)
             VALUES (?,?,?,?,?,?)'
        )->execute([$uid, $parcela['id'], $parcela['cultivo'], $kg, $fechaC, $notas !== '' ? $notas : null]);
        break;

    default:
        fallar('Acción no válida.');
}

responder(['ok' => true, 'datos' => estado($conexion, $uid)]);

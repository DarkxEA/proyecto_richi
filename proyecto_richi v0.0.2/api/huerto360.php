<?php
require __DIR__ . '/_comun.php';

$d = entrada();
// SOLO EL ADMINISTRADOR PUEDE ENTRAR A HUERTO360
$yo = requerir_usuario($conexion, ['admin']);

function estado(PDO $bd): array
{
    // Sincronizar estado de tareas completadas por el jornalero hacia tareas_huerto
    $bd->exec(
        "UPDATE tareas_huerto th
           JOIN tareas_jornalero tj ON tj.id = th.tarea_jornalero_id
            SET th.hecha = IF(tj.estado = 'Completada', 1, 0)"
    );

    return [
        'adminName' => $_SESSION['admin_name'] ?? 'Administrador',
        'crops' => array_map(fn($r) => [
            'id' => (int)$r['id'], 'name' => $r['nombre'], 'icon' => $r['icono'], 'health' => (int)$r['salud'],
        ], $bd->query('SELECT id, nombre, icono, salud FROM cultivos ORDER BY id')->fetchAll()),

        'zones' => array_map(fn($r) => [
            'id' => (int)$r['id'], 'name' => $r['nombre'], 'humidity' => (int)$r['humedad'], 'auto' => (bool)$r['riego_auto'],
        ], $bd->query('SELECT id, nombre, humedad, riego_auto FROM zonas ORDER BY id')->fetchAll()),

        'tasks' => array_map(fn($r) => [
            'id' => (int)$r['id'], 'text' => $r['texto'], 'date' => $r['fecha'],
            'minutes' => (int)$r['minutos'], 'done' => (bool)$r['hecha'], 'zone' => $r['zona'] ?? 'Invernadero',
        ], $bd->query('SELECT id, texto, fecha, minutos, hecha, zona FROM tareas_huerto ORDER BY id')->fetchAll()),

        'events' => array_map(fn($r) => [
            'id' => (int)$r['id'], 'date' => $r['fecha'], 'text' => $r['texto'],
        ], $bd->query('SELECT id, fecha, texto FROM eventos ORDER BY id')->fetchAll()),

        'stock' => array_map(fn($r) => [
            'id' => (int)$r['id'], 'name' => $r['nombre'], 'quantity' => (float)$r['cantidad'],
        ], $bd->query('SELECT id, nombre, cantidad FROM inventario ORDER BY id')->fetchAll()),

        // Visibilidad 360: Reportes de campo del Jornalero
        'fieldReports' => array_map(fn($r) => [
            'id' => (int)$r['id'], 'type' => $r['tipo'], 'zone' => $r['zona'],
            'description' => $r['descripcion'], 'date' => $r['fecha'], 'author' => $r['autor'] ?? 'Jornalero',
        ], $bd->query(
            'SELECT r.id, r.tipo, r.zona, r.descripcion, r.fecha, u.nombre AS autor
               FROM reportes r LEFT JOIN usuarios u ON u.id = r.usuario_id
              ORDER BY r.id DESC LIMIT 20'
        )->fetchAll()),

        'deliveriesSummary' => $bd->query(
            "SELECT estado, COUNT(*) AS total FROM entregas GROUP BY estado"
        )->fetchAll(),
    ];
}

function minutos($v): int
{
    if (!is_numeric($v) || (int)$v < 1 || (int)$v > 1440) {
        fallar('Los minutos no son válidos.');
    }
    return (int)$v;
}

function cantidad($v): float
{
    if (!is_numeric($v) || (float)$v <= 0) {
        fallar('La cantidad debe ser mayor a cero.');
    }
    return (float)$v;
}

$id = (int)($d['id'] ?? 0);

switch ($d['accion'] ?? '') {
    case 'cargar':
        break;

    case 'regar':
        $conexion->prepare('UPDATE zonas SET humedad = LEAST(100, humedad + 15) WHERE id = ?')->execute([$id]);
        break;

    case 'riego_auto':
        $conexion->prepare('UPDATE zonas SET riego_auto = ? WHERE id = ?')->execute([!empty($d['auto']) ? 1 : 0, $id]);
        break;

    case 'salud':
        $h = $d['health'] ?? null;
        if (!is_numeric($h) || (int)$h != $h || $h < 0 || $h > 100) {
            fallar('Ingresa un número entero entre 0 y 100.');
        }
        $conexion->prepare('UPDATE cultivos SET salud = ? WHERE id = ?')->execute([(int)$h, $id]);
        break;

    case 'alternar_tarea':
        $done = !empty($d['done']) ? 1 : 0;
        $conexion->prepare('UPDATE tareas_huerto SET hecha = ? WHERE id = ?')->execute([$done, $id]);
        // Sincronizar también en tareas_jornalero
        $st = $conexion->prepare('SELECT tarea_jornalero_id FROM tareas_huerto WHERE id = ?');
        $st->execute([$id]);
        $tjid = $st->fetchColumn();
        if ($tjid) {
            $estadoJ = $done ? 'Completada' : 'Pendiente';
            $conexion->prepare('UPDATE tareas_jornalero SET estado = ? WHERE id = ?')->execute([$estadoJ, $tjid]);
        }
        break;

    case 'editar_tarea':
        $txt = texto($d['text'] ?? '', 200, 'La tarea');
        $fec = fecha($d['date'] ?? '');
        $min = minutos($d['minutes'] ?? 10);
        $conexion->prepare('UPDATE tareas_huerto SET texto = ?, fecha = ?, minutos = ? WHERE id = ?')
                 ->execute([$txt, $fec, $min, $id]);
        break;

    case 'crear_cultivo':
        $nombreCultivo = texto($d['name'] ?? '', 80, 'El cultivo');
        $iconoCultivo  = texto_opcional($d['icon'] ?? '🌱', 10, 'El icono') ?: '🌱';
        $conexion->prepare('INSERT INTO cultivos (nombre, icono, salud) VALUES (?,?,100)')
                 ->execute([$nombreCultivo, $iconoCultivo]);
        // Sincronizar en catálogo de productos para clientes si no existe
        $conexion->prepare('INSERT IGNORE INTO productos (nombre, icono, precio, stock) VALUES (?,?,2500,0)')
                 ->execute([$nombreCultivo, $iconoCultivo]);
        break;

    case 'crear_tarea':
        $txt  = texto($d['text'] ?? '', 200, 'La tarea');
        $fec  = fecha($d['date'] ?? '');
        if ($fec < hoy()) {
            fallar('La fecha de la tarea no puede ser anterior a hoy.');
        }
        $min  = minutos($d['minutes'] ?? 10);
        $zona = opcion($d['zone'] ?? 'Invernadero', ['Invernadero', 'Exterior', 'Huerto norte'], 'La zona');

        // 1. Insertar en tareas_jornalero para que el Jornalero la vea en su panel
        $conexion->prepare('INSERT INTO tareas_jornalero (nombre, zona, fecha, estado) VALUES (?,?,?,\'Pendiente\')')
                 ->execute([$txt, $zona, $fec]);
        $tjid = (int)$conexion->lastInsertId();

        // 2. Insertar en tareas_huerto ligada a tareas_jornalero
        $conexion->prepare('INSERT INTO tareas_huerto (texto, fecha, minutos, zona, tarea_jornalero_id) VALUES (?,?,?,?,?)')
                 ->execute([$txt, $fec, $min, $zona, $tjid]);
        break;

    case 'crear_evento':
        $fec = fecha($d['date'] ?? '');
        $txt = texto($d['text'] ?? '', 200, 'El evento');
        $conexion->prepare('INSERT INTO eventos (fecha, texto) VALUES (?,?)')->execute([$fec, $txt]);
        break;

    case 'crear_inventario':
        $conexion->prepare('INSERT INTO inventario (nombre, cantidad) VALUES (?,?)')->execute([
            texto($d['name'] ?? '', 100, 'El artículo'), cantidad($d['quantity'] ?? null),
        ]);
        break;

    case 'eliminar':
        $tablas = ['cultivo' => 'cultivos', 'tarea' => 'tareas_huerto', 'evento' => 'eventos', 'inventario' => 'inventario'];
        $tabla = $tablas[$d['tabla'] ?? ''] ?? null;
        if (!$tabla) {
            fallar('Registro no válido.');
        }
        if ($tabla === 'tareas_huerto') {
            $st = $conexion->prepare('SELECT tarea_jornalero_id FROM tareas_huerto WHERE id = ?');
            $st->execute([$id]);
            $tjid = $st->fetchColumn();
            if ($tjid) {
                $conexion->prepare('DELETE FROM tareas_jornalero WHERE id = ?')->execute([$tjid]);
            }
        }
        $conexion->prepare("DELETE FROM $tabla WHERE id = ?")->execute([$id]);
        break;

    default:
        fallar('Acción no válida.');
}

responder(['ok' => true, 'datos' => estado($conexion)]);


/*require __DIR__ . '/_comun.php';

$d = entrada();
requerir_usuario($conexion);   // cualquier usuario con sesión; los datos del huerto son compartidos

/** Estado completo del huerto, con la misma forma que usa huerto360.html */
/*function estado(PDO $bd): array
{
    return [
        'crops' => array_map(fn($r) => [
            'id' => (int)$r['id'], 'name' => $r['nombre'], 'icon' => $r['icono'], 'health' => (int)$r['salud'],
        ], $bd->query('SELECT id, nombre, icono, salud FROM cultivos ORDER BY id')->fetchAll()),

        'zones' => array_map(fn($r) => [
            'id' => (int)$r['id'], 'name' => $r['nombre'], 'humidity' => (int)$r['humedad'], 'auto' => (bool)$r['riego_auto'],
        ], $bd->query('SELECT id, nombre, humedad, riego_auto FROM zonas ORDER BY id')->fetchAll()),

        'tasks' => array_map(fn($r) => [
            'id' => (int)$r['id'], 'text' => $r['texto'], 'date' => $r['fecha'],
            'minutes' => (int)$r['minutos'], 'done' => (bool)$r['hecha'],
        ], $bd->query('SELECT id, texto, fecha, minutos, hecha FROM tareas_huerto ORDER BY id')->fetchAll()),

        'events' => array_map(fn($r) => [
            'id' => (int)$r['id'], 'date' => $r['fecha'], 'text' => $r['texto'],
        ], $bd->query('SELECT id, fecha, texto FROM eventos ORDER BY id')->fetchAll()),

        'stock' => array_map(fn($r) => [
            'id' => (int)$r['id'], 'name' => $r['nombre'], 'quantity' => (float)$r['cantidad'],
        ], $bd->query('SELECT id, nombre, cantidad FROM inventario ORDER BY id')->fetchAll()),
    ];
}

function minutos($v): int
{
    if (!is_numeric($v) || (int)$v < 1 || (int)$v > 1440) {
        fallar('Los minutos no son válidos.');
    }
    return (int)$v;
}

function cantidad($v): float
{
    if (!is_numeric($v) || (float)$v < 0) {
        fallar('La cantidad no es válida.');
    }
    return (float)$v;
}

function reemplazar_todo(PDO $bd, array $v): void
{
    foreach (['crops', 'zones', 'tasks', 'events'] as $k) {
        if (!isset($v[$k]) || !is_array($v[$k]) || count($v[$k]) > 500) {
            fallar('Formato no válido.');
        }
    }
    $stockLista = isset($v['stock']) && is_array($v['stock']) ? array_slice($v['stock'], 0, 500) : [];

    $bd->beginTransaction();
    try {
        foreach (['cultivos', 'zonas', 'tareas_huerto', 'eventos', 'inventario'] as $t) {
            $bd->exec("DELETE FROM $t");
        }
        $c = $bd->prepare('INSERT INTO cultivos (nombre, icono, salud) VALUES (?,?,?)');
        foreach ($v['crops'] as $x) {
            $c->execute([texto($x['name'] ?? '', 80, 'El cultivo'), texto_opcional($x['icon'] ?? '🌱', 10, 'El icono') ?: '🌱',
                         max(0, min(100, (int)($x['health'] ?? 100)))]);
        }
        $z = $bd->prepare('INSERT INTO zonas (nombre, humedad, riego_auto) VALUES (?,?,?)');
        foreach ($v['zones'] as $x) {
            $z->execute([texto($x['name'] ?? '', 80, 'La zona'), max(0, min(100, (int)($x['humidity'] ?? 50))), !empty($x['auto']) ? 1 : 0]);
        }
        $t = $bd->prepare('INSERT INTO tareas_huerto (texto, fecha, minutos, hecha) VALUES (?,?,?,?)');
        foreach ($v['tasks'] as $x) {
            $t->execute([texto($x['text'] ?? '', 200, 'La tarea'), fecha($x['date'] ?? ''), minutos($x['minutes'] ?? 10), !empty($x['done']) ? 1 : 0]);
        }
        $e = $bd->prepare('INSERT INTO eventos (fecha, texto) VALUES (?,?)');
        foreach ($v['events'] as $x) {
            $e->execute([fecha($x['date'] ?? ''), texto($x['text'] ?? '', 200, 'El evento')]);
        }
        $s = $bd->prepare('INSERT INTO inventario (nombre, cantidad) VALUES (?,?)');
        foreach ($stockLista as $x) {
            $s->execute([texto($x['name'] ?? '', 100, 'El artículo'), cantidad($x['quantity'] ?? 0)]);
        }
        $bd->commit();
    } catch (Throwable $err) {
        $bd->rollBack();
        throw $err;
    }
}

$id = (int)($d['id'] ?? 0);

switch ($d['accion'] ?? '') {
    case 'cargar':
        break;

    case 'regar':
        $conexion->prepare('UPDATE zonas SET humedad = LEAST(100, humedad + 15) WHERE id = ?')->execute([$id]);
        break;

    case 'riego_auto':
        $conexion->prepare('UPDATE zonas SET riego_auto = ? WHERE id = ?')->execute([!empty($d['auto']) ? 1 : 0, $id]);
        break;

    case 'salud':
        $h = $d['health'] ?? null;
        if (!is_numeric($h) || (int)$h != $h || $h < 0 || $h > 100) {
            fallar('Ingresa un número entero entre 0 y 100.');
        }
        $conexion->prepare('UPDATE cultivos SET salud = ? WHERE id = ?')->execute([(int)$h, $id]);
        break;

    case 'alternar_tarea':
        $conexion->prepare('UPDATE tareas_huerto SET hecha = ? WHERE id = ?')->execute([!empty($d['done']) ? 1 : 0, $id]);
        break;

    case 'editar_tarea':
        $conexion->prepare('UPDATE tareas_huerto SET texto = ?, fecha = ?, minutos = ? WHERE id = ?')->execute([
            texto($d['text'] ?? '', 200, 'La tarea'), fecha($d['date'] ?? ''), minutos($d['minutes'] ?? 0), $id,
        ]);
        break;

    case 'crear_cultivo':
        $conexion->prepare('INSERT INTO cultivos (nombre, icono, salud) VALUES (?,?,100)')->execute([
            texto($d['name'] ?? '', 80, 'El cultivo'), texto_opcional($d['icon'] ?? '🌱', 10, 'El icono') ?: '🌱',
        ]);
        break;

    case 'crear_tarea':
        $conexion->prepare('INSERT INTO tareas_huerto (texto, fecha, minutos) VALUES (?,?,?)')->execute([
            texto($d['text'] ?? '', 200, 'La tarea'), fecha($d['date'] ?? ''), minutos($d['minutes'] ?? 0),
        ]);
        break;

    case 'crear_evento':
        $conexion->prepare('INSERT INTO eventos (fecha, texto) VALUES (?,?)')->execute([
            fecha($d['date'] ?? ''), texto($d['text'] ?? '', 200, 'El evento'),
        ]);
        break;

    case 'crear_inventario':
        $conexion->prepare('INSERT INTO inventario (nombre, cantidad) VALUES (?,?)')->execute([
            texto($d['name'] ?? '', 100, 'El artículo'), cantidad($d['quantity'] ?? null),
        ]);
        break;

    case 'eliminar':
        $tablas = ['cultivo' => 'cultivos', 'tarea' => 'tareas_huerto', 'evento' => 'eventos', 'inventario' => 'inventario'];
        $tabla = $tablas[$d['tabla'] ?? ''] ?? null;
        if (!$tabla) {
            fallar('Registro no válido.');
        }
        $conexion->prepare("DELETE FROM $tabla WHERE id = ?")->execute([$id]);
        break;

    case 'importar':
        reemplazar_todo($conexion, is_array($d['datos'] ?? null) ? $d['datos'] : []);
        break;

    case 'reiniciar':
        reemplazar_todo($conexion, [
            'crops' => [
                ['name' => 'Tomate', 'icon' => '🍅', 'health' => 85], ['name' => 'Lechuga', 'icon' => '🥬', 'health' => 72],
                ['name' => 'Zanahoria', 'icon' => '🥕', 'health' => 91], ['name' => 'Maíz', 'icon' => '🌽', 'health' => 64],
            ],
            'zones' => [
                ['name' => 'Invernadero', 'humidity' => 85, 'auto' => false],
                ['name' => 'Exterior', 'humidity' => 72, 'auto' => true],
                ['name' => 'Huerto norte', 'humidity' => 61, 'auto' => false],
            ],
            'tasks' => [
                ['text' => 'Revisar humedad de Zona 3', 'date' => hoy(), 'minutes' => 10],
                ['text' => 'Cosechar lechuga madura', 'date' => hoy(), 'minutes' => 15],
                ['text' => 'Preparar fertilizante orgánico', 'date' => hoy(), 'minutes' => 20],
            ],
            'events' => [['text' => 'Revisión de riego', 'date' => hoy()]],
            'stock'  => [],
        ]);
        break;

    default:
        fallar('Acción no válida.');
}

responder(['ok' => true, 'datos' => estado($conexion)]);
*/
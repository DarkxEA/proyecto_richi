<?php
require __DIR__ . '/_comun.php';

$d = entrada();
requerir_usuario($conexion);   // cualquier usuario con sesión; los datos del huerto son compartidos

/** Estado completo del huerto, con la misma forma que usa huerto360.html */
function estado(PDO $bd): array
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

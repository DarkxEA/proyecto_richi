<?php
require __DIR__ . '/_comun.php';

$d  = entrada();
$yo = requerir_usuario($conexion, ['trasportista']);
$uid = (int)$yo['id'];

/** Estado completo del transportista, con la misma forma que usa Trasportista.html */
function estado(PDO $bd, int $uid): array
{
    // Entregas asignadas a este transportista + entregas libres que cualquiera puede tomar
    $st = $bd->prepare(
        'SELECT id, cliente, direccion, cultivo, cantidad, fecha, estado, nota, entregada_en
           FROM entregas WHERE transportista_id IS NULL OR transportista_id = ? ORDER BY id'
    );
    $st->execute([$uid]);
    $deliveries = array_map(fn($r) => [
        'id'          => (int)$r['id'],
        'client'      => $r['cliente'],
        'address'     => $r['direccion'],
        'crop'        => $r['cultivo'],
        'amount'      => (float)$r['cantidad'],
        'date'        => $r['fecha'],
        'status'      => $r['estado'],
        'note'        => $r['nota'] ?? '',
        'deliveredAt' => iso($r['entregada_en']),
    ], $st->fetchAll());

    $st = $bd->prepare(
        'SELECT i.id, i.entrega_id, i.tipo, i.detalles, i.creada_en
           FROM incidencias i JOIN entregas e ON e.id = i.entrega_id
          WHERE e.transportista_id = ? OR e.transportista_id IS NULL ORDER BY i.id'
    );
    $st->execute([$uid]);
    $incidents = array_map(fn($r) => [
        'id'        => (int)$r['id'],
        'order'     => (int)$r['entrega_id'],
        'type'      => $r['tipo'],
        'details'   => $r['detalles'],
        'createdAt' => iso($r['creada_en']),
    ], $st->fetchAll());

    return ['deliveries' => $deliveries, 'incidents' => $incidents];
}

$id = (int)($d['id'] ?? 0);

switch ($d['accion'] ?? '') {
    case 'cargar':
        break;

    case 'iniciar':
        // Un solo UPDATE: si dos transportistas lo intentan a la vez, solo uno lo obtiene
        $st = $conexion->prepare(
            'UPDATE entregas SET estado = \'En ruta\', transportista_id = ?
              WHERE id = ? AND estado = \'Pendiente\' AND (transportista_id IS NULL OR transportista_id = ?)'
        );
        $st->execute([$uid, $id, $uid]);
        if ($st->rowCount() === 0) {
            fallar('Esta entrega ya no está disponible.');
        }
        break;

    case 'entregar':
        $st = $conexion->prepare(
            'UPDATE entregas SET estado = \'Entregada\', entregada_en = ?
              WHERE id = ? AND estado = \'En ruta\' AND transportista_id = ?'
        );
        $st->execute([ahora(), $id, $uid]);
        if ($st->rowCount() === 0) {
            fallar('No se pudo actualizar la entrega.');
        }
        break;

    case 'fallar':
        $nota = texto($d['note'] ?? '', 500, 'El motivo');
        $st = $conexion->prepare(
            'UPDATE entregas SET estado = \'No entregada\', nota = ?, entregada_en = ?
              WHERE id = ? AND estado = \'En ruta\' AND transportista_id = ?'
        );
        $st->execute([$nota, ahora(), $id, $uid]);
        if ($st->rowCount() === 0) {
            fallar('No se pudo actualizar la entrega.');
        }
        break;

    case 'incidencia':
        $entrega = (int)($d['order'] ?? 0);
        $tipo    = opcion($d['type'] ?? '', ['Retraso', 'Vehículo', 'Producto dañado', 'Dirección incorrecta', 'Otro'], 'El tipo de incidencia');
        $detalle = texto($d['details'] ?? '', 1000, 'Los detalles');

        $st = $conexion->prepare(
            'SELECT 1 FROM entregas WHERE id = ? AND (transportista_id IS NULL OR transportista_id = ?)'
        );
        $st->execute([$entrega, $uid]);
        if (!$st->fetch()) {
            fallar('La entrega no existe.', 404);
        }
        $conexion->prepare(
            'INSERT INTO incidencias (entrega_id, tipo, detalles, creada_en) VALUES (?,?,?,?)'
        )->execute([$entrega, $tipo, $detalle, ahora()]);
        break;

    default:
        fallar('Acción no válida.');
}

responder(['ok' => true, 'datos' => estado($conexion, $uid)]);

<?php
require __DIR__ . '/_comun.php';

$d  = entrada();
$yo = requerir_usuario($conexion, ['cliente']);
$uid = (int)$yo['id'];

/** Estado completo del cliente, con la misma forma que usa cliente.html (precios en centavos). */
function estado(PDO $bd, int $uid): array
{
    $st = $bd->prepare('SELECT nombre, telefono, direccion FROM usuarios WHERE id = ?');
    $st->execute([$uid]);
    $u = $st->fetch();
    $profile = [
        'name'    => $u['nombre'],
        'phone'   => $u['telefono'] ?? '',
        'address' => $u['direccion'] ?? '',
    ];

    $products = array_map(fn($r) => [
        'id'    => (int)$r['id'],
        'name'  => $r['nombre'],
        'icon'  => $r['icono'],
        'price' => (int)$r['precio'],
        'stock' => (int)$r['stock'],
    ], $bd->query('SELECT id, nombre, icono, precio, stock FROM productos ORDER BY id')->fetchAll());

    $st = $bd->prepare('SELECT producto_id, cantidad FROM carrito_items WHERE usuario_id = ? ORDER BY producto_id');
    $st->execute([$uid]);
    $cart = array_map(fn($r) => [
        'id'       => (int)$r['producto_id'],
        'quantity' => (int)$r['cantidad'],
    ], $st->fetchAll());

    $st = $bd->prepare(
        'SELECT numero, cliente_nombre, telefono, direccion, total, estado, creado_en
           FROM pedidos WHERE usuario_id = ? ORDER BY numero'
    );
    $st->execute([$uid]);
    $pedidos = $st->fetchAll();

    $orders = [];
    foreach ($pedidos as $p) {
        $it = $bd->prepare(
            'SELECT i.producto_id, i.nombre, i.precio, i.cantidad, COALESCE(pr.icono, \'🌱\') AS icono
               FROM pedido_items i LEFT JOIN productos pr ON pr.id = i.producto_id
              WHERE i.pedido_numero = ? ORDER BY i.id'
        );
        $it->execute([$p['numero']]);
        $orders[] = [
            'number'    => (int)$p['numero'],
            'items'     => array_map(fn($r) => [
                'id'       => (int)$r['producto_id'],
                'name'     => $r['nombre'],
                'icon'     => $r['icono'],
                'price'    => (int)$r['precio'],
                'quantity' => (int)$r['cantidad'],
            ], $it->fetchAll()),
            'total'     => (int)$p['total'],
            'customer'  => [
                'name'    => $p['cliente_nombre'],
                'phone'   => $p['telefono'],
                'address' => $p['direccion'],
            ],
            'createdAt' => iso($p['creado_en']),
            'status'    => $p['estado'],
        ];
    }

    return ['profile' => $profile, 'products' => $products, 'cart' => $cart, 'orders' => $orders];
}

/** Valida nombre, teléfono (10 dígitos) y dirección del formulario. */
function datos_cliente(array $d): array
{
    $nombre = texto($d['name'] ?? '', 100, 'El nombre');
    $dir    = texto($d['address'] ?? '', 255, 'La dirección');
    $tel    = trim((string)($d['phone'] ?? ''));
    if (!preg_match('/^[0-9]{10}$/', $tel)) {
        fallar('El teléfono debe tener 10 dígitos.');
    }
    return [$nombre, $tel, $dir];
}

function guardar_perfil(PDO $bd, int $uid, string $nombre, string $tel, string $dir): void
{
    $bd->prepare('UPDATE usuarios SET nombre = ?, telefono = ?, direccion = ? WHERE id = ?')
       ->execute([$nombre, $tel, $dir, $uid]);
}

switch ($d['accion'] ?? '') {
    case 'cargar':
        break;

    case 'agregar':
        $idp = (int)($d['id'] ?? 0);
        $st = $conexion->prepare('SELECT stock FROM productos WHERE id = ?');
        $st->execute([$idp]);
        $prod = $st->fetch();
        if (!$prod) {
            fallar('El producto no existe.', 404);
        }
        $st = $conexion->prepare('SELECT cantidad FROM carrito_items WHERE usuario_id = ? AND producto_id = ?');
        $st->execute([$uid, $idp]);
        $actual = (int)($st->fetchColumn() ?: 0);
        if ($actual >= (int)$prod['stock']) {
            fallar('No hay más cantidad disponible de este producto.');
        }
        $conexion->prepare(
            'INSERT INTO carrito_items (usuario_id, producto_id, cantidad) VALUES (?,?,1)
             ON DUPLICATE KEY UPDATE cantidad = cantidad + 1'
        )->execute([$uid, $idp]);
        break;

    case 'restar':
        $idp = (int)($d['id'] ?? 0);
        $conexion->prepare(
            'UPDATE carrito_items SET cantidad = cantidad - 1 WHERE usuario_id = ? AND producto_id = ?'
        )->execute([$uid, $idp]);
        $conexion->prepare(
            'DELETE FROM carrito_items WHERE usuario_id = ? AND producto_id = ? AND cantidad <= 0'
        )->execute([$uid, $idp]);
        break;

    case 'quitar':
        $conexion->prepare('DELETE FROM carrito_items WHERE usuario_id = ? AND producto_id = ?')
                 ->execute([$uid, (int)($d['id'] ?? 0)]);
        break;

    case 'guardar_perfil':
        [$nombre, $tel, $dir] = datos_cliente($d);
        guardar_perfil($conexion, $uid, $nombre, $tel, $dir);
        break;

    case 'pedido':
        [$nombre, $tel, $dir] = datos_cliente($d);

        $conexion->beginTransaction();
        try {
            // Bloquea el carrito y el stock para que dos compras no vendan lo mismo
            $st = $conexion->prepare(
                'SELECT c.producto_id, c.cantidad, p.nombre, p.precio, p.stock
                   FROM carrito_items c JOIN productos p ON p.id = c.producto_id
                  WHERE c.usuario_id = ? FOR UPDATE'
            );
            $st->execute([$uid]);
            $lineas = $st->fetchAll();
            if (!$lineas) {
                throw new RuntimeException('Tu carrito está vacío.');
            }

            $total = 0;
            foreach ($lineas as $l) {
                if ((int)$l['cantidad'] > (int)$l['stock']) {
                    throw new RuntimeException('Revisa la disponibilidad de los productos.');
                }
                $total += (int)$l['precio'] * (int)$l['cantidad'];
            }

            $conexion->prepare(
                'INSERT INTO pedidos (usuario_id, cliente_nombre, telefono, direccion, total, estado, creado_en)
                 VALUES (?,?,?,?,?,\'Pendiente\',?)'
            )->execute([$uid, $nombre, $tel, $dir, $total, ahora()]);
            $numero = (int)$conexion->lastInsertId();

            $insItem = $conexion->prepare(
                'INSERT INTO pedido_items (pedido_numero, producto_id, nombre, precio, cantidad) VALUES (?,?,?,?,?)'
            );
            $resta = $conexion->prepare('UPDATE productos SET stock = stock - ? WHERE id = ?');
            // Cada producto del pedido queda como una entrega para los transportistas
            $insEntrega = $conexion->prepare(
                'INSERT INTO entregas (pedido_numero, cliente, direccion, cultivo, cantidad, fecha)
                 VALUES (?,?,?,?,?,?)'
            );
            foreach ($lineas as $l) {
                $insItem->execute([$numero, $l['producto_id'], $l['nombre'], $l['precio'], $l['cantidad']]);
                $resta->execute([$l['cantidad'], $l['producto_id']]);
                $insEntrega->execute([$numero, $nombre, $dir, $l['nombre'], $l['cantidad'], hoy()]);
            }

            $conexion->prepare('DELETE FROM carrito_items WHERE usuario_id = ?')->execute([$uid]);
            guardar_perfil($conexion, $uid, $nombre, $tel, $dir);

            $conexion->commit();
        } catch (RuntimeException $e) {
            $conexion->rollBack();
            fallar($e->getMessage());
        } catch (Throwable $e) {
            $conexion->rollBack();
            throw $e;
        }
        break;

    case 'cancelar':
        $numero = (int)($d['id'] ?? 0);

        $conexion->beginTransaction();
        try {
            $st = $conexion->prepare('SELECT estado FROM pedidos WHERE numero = ? AND usuario_id = ? FOR UPDATE');
            $st->execute([$numero, $uid]);
            $ped = $st->fetch();
            if (!$ped) {
                throw new RuntimeException('El pedido no existe.');
            }
            if ($ped['estado'] !== 'Pendiente') {
                throw new RuntimeException('Solo se pueden cancelar pedidos pendientes.');
            }

            $st = $conexion->prepare(
                'SELECT COUNT(*) FROM entregas WHERE pedido_numero = ? AND estado <> \'Pendiente\''
            );
            $st->execute([$numero]);
            if ((int)$st->fetchColumn() > 0) {
                throw new RuntimeException('El pedido ya va en camino y no se puede cancelar.');
            }

            $conexion->prepare(
                'UPDATE productos p JOIN pedido_items i ON i.producto_id = p.id
                    SET p.stock = p.stock + i.cantidad
                  WHERE i.pedido_numero = ?'
            )->execute([$numero]);
            $conexion->prepare('DELETE FROM entregas WHERE pedido_numero = ?')->execute([$numero]);
            $conexion->prepare('UPDATE pedidos SET estado = \'Cancelado\' WHERE numero = ?')->execute([$numero]);

            $conexion->commit();
        } catch (RuntimeException $e) {
            $conexion->rollBack();
            fallar($e->getMessage());
        } catch (Throwable $e) {
            $conexion->rollBack();
            throw $e;
        }
        break;

    default:
        fallar('Acción no válida.');
}

responder(['ok' => true, 'datos' => estado($conexion, $uid)]);

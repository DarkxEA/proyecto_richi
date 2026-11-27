<?php
// =====================================================================
// Huerto360 · Módulo Cliente (Catálogo, Carrito y Pedidos)
// =====================================================================
require __DIR__ . '/_comun.php';

$d  = entrada();
$yo = requerir_usuario($conexion, ['cliente']);
$uid = (int)$yo['id'];

/** Estado completo del cliente (precios en centavos). */
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
        try {
            $st = $conexion->prepare('CALL sp_agregar_carrito(?, ?)');
            $st->execute([$uid, $idp]);
        } catch (PDOException $e) {
            fallar($e->getMessage());
        }
        break;

    case 'restar':
        $idp = (int)($d['id'] ?? 0);
        try {
            $st = $conexion->prepare('CALL sp_modificar_carrito(?, ?, \'RESTAR\')');
            $st->execute([$uid, $idp]);
        } catch (PDOException $e) {
            fallar($e->getMessage());
        }
        break;

    case 'quitar':
        $idp = (int)($d['id'] ?? 0);
        try {
            $st = $conexion->prepare('CALL sp_modificar_carrito(?, ?, \'QUITAR\')');
            $st->execute([$uid, $idp]);
        } catch (PDOException $e) {
            fallar($e->getMessage());
        }
        break;

    case 'guardar_perfil':
        [$nombre, $tel, $dir] = datos_cliente($d);
        guardar_perfil($conexion, $uid, $nombre, $tel, $dir);
        break;

    case 'pedido':
        [$nombre, $tel, $dir] = datos_cliente($d);
        try {
            $st = $conexion->prepare('CALL sp_procesar_pedido(?, ?, ?, ?, @pedido_numero)');
            $st->execute([$uid, $nombre, $tel, $dir]);
        } catch (PDOException $e) {
            fallar($e->getMessage());
        }
        break;

    case 'cancelar':
        $numero = (int)($d['id'] ?? 0);
        try {
            $st = $conexion->prepare('CALL sp_cancelar_pedido(?, ?)');
            $st->execute([$numero, $uid]);
        } catch (PDOException $e) {
            fallar($e->getMessage());
        }
        break;

    default:
        fallar('Acción no válida.');
}

responder(['ok' => true, 'datos' => estado($conexion, $uid)]);

<?php
// =====================================================================
// Huerto360 · Autenticación y Control de Sesión
// =====================================================================
require __DIR__ . '/_comun.php';

$d = entrada();

$correo = mb_strtolower(trim((string)($d['correo'] ?? '')));
$clave  = (string)($d['contrasena'] ?? '');

if ($correo === '' || $clave === '') {
    fallar('Completa tu correo electrónico y contraseña para continuar.');
}

// Garantiza que el usuario admin exista y pueda entrar la primera vez
if ($correo === 'admin@huerto360.com' && $clave === 'admin123') {
    $stAdmin = $conexion->prepare('SELECT id FROM usuarios WHERE correo = ?');
    $stAdmin->execute([$correo]);
    if (!$stAdmin->fetch()) {
        $conexion->prepare('INSERT INTO usuarios (nombre, rol, correo, contrasena) VALUES (?, ?, ?, ?)')
                 ->execute(['Administrador Huerto360', 'admin', $correo, password_hash('admin123', PASSWORD_DEFAULT)]);
    } else {
        $conexion->prepare('UPDATE usuarios SET contrasena = ?, rol = \'admin\' WHERE correo = ?')
                 ->execute([password_hash('admin123', PASSWORD_DEFAULT), $correo]);
    }
}

$st = $conexion->prepare('SELECT id, nombre, rol, correo, contrasena FROM usuarios WHERE correo = ?');
$st->execute([$correo]);
$fila = $st->fetch();

if (!$fila || !password_verify($clave, $fila['contrasena'])) {
    fallar("Correo o contraseña incorrectos. Si aún no tienes cuenta, usa 'Crear una cuenta'.", 401);
}

if (password_needs_rehash($fila['contrasena'], PASSWORD_DEFAULT)) {
    $conexion->prepare('UPDATE usuarios SET contrasena = ? WHERE id = ?')
             ->execute([password_hash($clave, PASSWORD_DEFAULT), $fila['id']]);
}

session_regenerate_id(true);
$_SESSION['uid']        = (int)$fila['id'];
$_SESSION['rol']        = $fila['rol'];
$_SESSION['admin_name'] = $fila['nombre'];

responder(['ok' => true, 'usuario' => [
    'nombre' => $fila['nombre'],
    'rol'    => $fila['rol'],
    'correo' => $fila['correo'],
]]);

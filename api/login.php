<?php
require __DIR__ . '/_comun.php';

$d = entrada();

$correo = mb_strtolower(trim((string)($d['correo'] ?? '')));
$clave  = (string)($d['contrasena'] ?? '');

if ($correo === '' || $clave === '') {
    fallar('Completa tu correo electrónico y contraseña para continuar.');
}

$st = $conexion->prepare('SELECT id, nombre, rol, correo, contrasena FROM usuarios WHERE correo = ?');
$st->execute([$correo]);
$fila = $st->fetch();

if (!$fila || !password_verify($clave, $fila['contrasena'])) {
    fallar("Correo o contraseña incorrectos. Si aún no tienes cuenta, usa 'Crear una cuenta'.", 401);
}

// Si PHP mejora el algoritmo de hash en el futuro, se actualiza solo.
if (password_needs_rehash($fila['contrasena'], PASSWORD_DEFAULT)) {
    $conexion->prepare('UPDATE usuarios SET contrasena = ? WHERE id = ?')
             ->execute([password_hash($clave, PASSWORD_DEFAULT), $fila['id']]);
}

session_regenerate_id(true);
$_SESSION['uid'] = (int)$fila['id'];

responder(['ok' => true, 'usuario' => [
    'nombre' => $fila['nombre'],
    'rol'    => $fila['rol'],
    'correo' => $fila['correo'],
]]);

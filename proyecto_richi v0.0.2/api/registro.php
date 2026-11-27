<?php
require __DIR__ . '/_comun.php';

$d = entrada();

$nombre = texto($d['nombre'] ?? '', 100, 'El nombre');
if (!preg_match('/^[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ\s]{3,100}$/u', $nombre)) {
    fallar('El nombre solo debe contener letras y espacios (mínimo 3 letras).');
}

// 'admin' NO está permitido en el registro público
$rol    = opcion($d['rol'] ?? '', ['agricultor', 'cliente', 'jornalero', 'trasportista'], 'El rol');
$correo = mb_strtolower(trim((string)($d['correo'] ?? '')));
$clave  = (string)($d['contrasena'] ?? '');

if (!filter_var($correo, FILTER_VALIDATE_EMAIL) || mb_strlen($correo) > 150) {
    fallar('Ingresa un correo electrónico con formato válido.');
}

// Validación de contraseña segura (coincide con el checklist de index.html)
if (
    mb_strlen($clave) < 8 ||
    !preg_match('/[A-ZÁÉÍÓÚÑ]/u', $clave) ||
    !preg_match('/[a-záéíóúñ]/u', $clave) ||
    !preg_match('/[0-9]/', $clave)
) {
    fallar('La contraseña debe tener al menos 8 caracteres, una mayúscula, una minúscula y un número.');
}

$st = $conexion->prepare('SELECT 1 FROM usuarios WHERE correo = ?');
$st->execute([$correo]);
if ($st->fetch()) {
    fallar('Ya existe una cuenta con este correo. Por favor inicia sesión.', 409);
}

try {
    $st = $conexion->prepare(
        'INSERT INTO usuarios (nombre, rol, correo, contrasena) VALUES (?, ?, ?, ?)'
    );
    $st->execute([$nombre, $rol, $correo, password_hash($clave, PASSWORD_DEFAULT)]);
} catch (PDOException $e) {
    if ($e->getCode() === '23000') {
        fallar('Ya existe una cuenta con este correo. Por favor inicia sesión.', 409);
    }
    throw $e;
}

session_regenerate_id(true);
$_SESSION['uid'] = (int)$conexion->lastInsertId();

responder(['ok' => true, 'usuario' => ['nombre' => $nombre, 'rol' => $rol, 'correo' => $correo]], 201);


/*require __DIR__ . '/_comun.php';

$d = entrada();

$nombre = texto($d['nombre'] ?? '', 100, 'El nombre');
$rol    = opcion($d['rol'] ?? '', ['agricultor', 'cliente', 'jornalero', 'trasportista'], 'El rol');
$correo = mb_strtolower(trim((string)($d['correo'] ?? '')));
$clave  = (string)($d['contrasena'] ?? '');

if (!filter_var($correo, FILTER_VALIDATE_EMAIL) || mb_strlen($correo) > 150) {
    fallar('Ingresa un correo electrónico con formato válido.');
}
if (mb_strlen($clave) < 6) {
    fallar('La contraseña debe tener un mínimo de 6 caracteres.');
}

$st = $conexion->prepare('SELECT 1 FROM usuarios WHERE correo = ?');
$st->execute([$correo]);
if ($st->fetch()) {
    fallar('Ya existe una cuenta con este correo. Por favor inicia sesión.', 409);
}

try {
    $st = $conexion->prepare(
        'INSERT INTO usuarios (nombre, rol, correo, contrasena) VALUES (?, ?, ?, ?)'
    );
    $st->execute([$nombre, $rol, $correo, password_hash($clave, PASSWORD_DEFAULT)]);
} catch (PDOException $e) {
    if ($e->getCode() === '23000') {      // correo repetido (carrera entre dos registros)
        fallar('Ya existe una cuenta con este correo. Por favor inicia sesión.', 409);
    }
    throw $e;
}

session_regenerate_id(true);
$_SESSION['uid'] = (int)$conexion->lastInsertId();

responder(['ok' => true, 'usuario' => ['nombre' => $nombre, 'rol' => $rol, 'correo' => $correo]], 201);
*/
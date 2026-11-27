<?php
// =====================================================================
// Huerto360 · Registro Público de Usuarios
// =====================================================================
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

// Validación de contraseña segura
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

$nuevoId = (int)$conexion->lastInsertId();
session_regenerate_id(true);
$_SESSION['uid'] = $nuevoId;
$_SESSION['rol'] = $rol;

responder(['ok' => true, 'usuario' => ['nombre' => $nombre, 'rol' => $rol, 'correo' => $correo]], 201);

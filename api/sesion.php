<?php
// Devuelve el usuario con sesión iniciada (o 401 si no hay).
require __DIR__ . '/_comun.php';

$u = requerir_usuario($conexion);
responder(['usuario' => ['nombre' => $u['nombre'], 'rol' => $u['rol'], 'correo' => $u['correo']]]);

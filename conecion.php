<?php
// Conexión a la base de datos Huerto360 (XAMPP: usuario root, sin contraseña)
$servidor   = "localhost";
$usuario    = "root";
$contrasena = "";
$baseDatos  = "Huerto360";

try {
    $conexion = new PDO(
        "mysql:host=$servidor;dbname=$baseDatos;charset=utf8mb4",
        $usuario,
        $contrasena,
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]
    );
} catch (PDOException $e) {
    // Ya no se imprime texto suelto: las páginas esperan JSON.
    http_response_code(500);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['error' => 'Error al conectar con la base de datos'], JSON_UNESCAPED_UNICODE);
    exit;
}

<?php
// =====================================================================
// Huerto360 · Conexión Multi-Puerto y Fallback Automático (3306 y 3307)
// Soporta XAMPP estándar en puerto 3307/3306 con y sin contraseña.
// =====================================================================

$baseDatos = "Huerto360";
$usuario   = "root";

// En tu XAMPP MySQL está escuchando en el puerto 3307 (el 3306 lo ocupa otro servicio)
$puertosAProbar = [3307, 3306];
$hostsAProbar   = ["127.0.0.1", "localhost"];
$clavesAProbar  = ["admin234", "", "root"];

$conexion = null;
$errorDetalle = "";

foreach ($puertosAProbar as $puerto) {
    foreach ($hostsAProbar as $host) {
        foreach ($clavesAProbar as $clave) {
            try {
                $conexion = new PDO(
                    "mysql:host=$host;port=$puerto;dbname=$baseDatos;charset=utf8mb4",
                    $usuario,
                    $clave,
                    [
                        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                        PDO::ATTR_EMULATE_PREPARES   => false,
                    ]
                );
                break 3; // ¡Conexión exitosa!
            } catch (PDOException $e) {
                $errorDetalle = $e->getMessage();
            }
        }
    }
}

if (!$conexion) {
    http_response_code(500);
    header('Content-Type: application/json; charset=utf-8');
    
    $mensaje = 'Error al conectar con la base de datos Huerto360.';
    if (stripos($errorDetalle, 'Unknown database') !== false) {
        $mensaje = "Conexión a MySQL exitosa, pero la base de datos 'Huerto360' aún no ha sido creada. Por favor importa primero Huerto360.sql y luego SPs.sql en phpMyAdmin.";
    } elseif (stripos($errorDetalle, 'Access denied') !== false) {
        $mensaje = "Acceso denegado a MySQL para el usuario root. Revisa las contraseñas de MySQL.";
    } else {
        $mensaje .= " (Revisa puertos 3307/3306 y que MySQL esté activo. Detalle: $errorDetalle)";
    }
    
    echo json_encode(['error' => $mensaje], JSON_UNESCAPED_UNICODE);
    exit;
}

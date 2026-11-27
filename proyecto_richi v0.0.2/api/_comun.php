<?php
// Utilidades compartidas por todos los archivos de /api
declare(strict_types=1);

date_default_timezone_set('America/Mexico_City');

session_set_cookie_params([
    'lifetime' => 0,
    'path'     => '/',
    'httponly' => true,
    'samesite' => 'Lax',
]);
session_start();

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

require __DIR__ . '/../conecion.php';   // define $conexion (PDO)

function responder(array $datos, int $codigo = 200): void
{
    http_response_code($codigo);
    echo json_encode($datos, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function fallar(string $mensaje, int $codigo = 400): void
{
    responder(['error' => $mensaje], $codigo);
}

/** Solo acepta POST y devuelve el cuerpo JSON como arreglo. */
function entrada(): array
{
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
        fallar('Método no permitido.', 405);
    }
    $crudo = file_get_contents('php://input');
    $json  = json_decode($crudo === false ? '' : $crudo, true);
    return is_array($json) ? $json : [];
}

/** Exige sesión iniciada. Si se pasan roles, también exige que coincida. */
function requerir_usuario(PDO $bd, array $roles = []): array
{
    $id = $_SESSION['uid'] ?? null;
    if (!$id) {
        fallar('Debes iniciar sesión.', 401);
    }
    $st = $bd->prepare('SELECT id, nombre, rol, correo, telefono, direccion FROM usuarios WHERE id = ?');
    $st->execute([(int)$id]);
    $fila = $st->fetch();
    if (!$fila) {
        session_unset();
        fallar('Debes iniciar sesión.', 401);
    }
    if ($roles && !in_array($fila['rol'], $roles, true)) {
        fallar('No tienes permiso para esta sección.', 403);
    }
    return $fila;
}

function texto($valor, int $max, string $campo): string
{
    $t = trim((string)($valor ?? ''));
    if ($t === '') {
        fallar("Falta: $campo.");
    }
    if (mb_strlen($t) > $max) {
        fallar("$campo es demasiado largo (máximo $max caracteres).");
    }
    return $t;
}

function texto_opcional($valor, int $max, string $campo): string
{
    $t = trim((string)($valor ?? ''));
    if (mb_strlen($t) > $max) {
        fallar("$campo es demasiado largo (máximo $max caracteres).");
    }
    return $t;
}

function fecha($valor, string $campo = 'La fecha'): string
{
    $v = (string)($valor ?? '');
    $d = DateTime::createFromFormat('Y-m-d', $v);
    if (!$d || $d->format('Y-m-d') !== $v) {
        fallar("$campo no es válida.");
    }
    return $v;
}

function numero_positivo($valor, string $campo): float
{
    if (!is_numeric($valor) || (float)$valor <= 0) {
        fallar("$campo debe ser un número mayor que cero.");
    }
    return (float)$valor;
}

function opcion($valor, array $permitidas, string $campo): string
{
    $v = (string)($valor ?? '');
    if (!in_array($v, $permitidas, true)) {
        fallar("$campo no es válido.");
    }
    return $v;
}

function hoy(): string
{
    return date('Y-m-d');
}

function ahora(): string
{
    return date('Y-m-d H:i:s');
}

/** DATETIME de MySQL -> ISO 8601 (lo que espera new Date() en el navegador). */
function iso(?string $dt): ?string
{
    return $dt ? (new DateTime($dt))->format('c') : null;
}

# 🌻 HUERTO360 — Documentación de Cambios y Optimizaciones (Versión 0.0.3)

Sistema web de gestión agrícola integral diseñado con enfoque de **accesibilidad para adultos mayores**, control estricto de roles y sincronización automatizada entre módulos mediante **PHP + MySQL/MariaDB**.

---

## 🔍 Diagnóstico de la Versión 0.0.2: ¿Estaba optimizada al 100%?

**Respuesta: No.** Aunque la versión 0.0.2 incorporó avances significativos (validación de contraseñas, roles e integración con procedimientos almacenados), un análisis exhaustivo del código reveló que **no estaba optimizada al 100%** y presentaba varias oportunidades críticas de mejora:

1. **Incompletitud en scripts SQL (`SPs.sql` y `Huerto360.sql`):**
   * El archivo maestro `SPs.sql` de la v0.0.2 solo contenía 5 de los 13 procedimientos almacenados (`sp_registrar_cosecha_agricultor`, `sp_registrar_jornada`, `sp_iniciar_entrega`, `sp_confirmar_entrega` y `sp_reportar_entrega_fallida`). Los otros 8 SPs estaban dispersos en archivos sueltos. Si un usuario corría `Huerto360.sql` y `SPs.sql`, el sistema fallaba en pedidos, carrito, incidencias y parcelas con errores de procedimiento inexistente.
   * `Huerto360.sql` no incluía el rol `admin` en el `ENUM` de la tabla `usuarios` ni los estados extendidos de pedidos (`En ruta`, `No entregada`), dependiendo forzosamente de parches manuales adicionales.
2. **Deuda técnica y código muerto (Comentarios masivos en Backend):**
   * A pesar de lo mencionado en el README anterior, persistían cientos de líneas comentadas residuales (`/* ... */`) en `api/login.php`, `api/registro.php`, `api/jornalero.php`, `api/huerto360.php`, `api/cliente.php`, `api/agricultor.php` y `api/transportista.php`.
3. **Rigidez de conexión (`conecion.php`):**
   * Tenía la contraseña `admin234` fija. En cualquier instalación típica de XAMPP (donde el usuario `root` no tiene contraseña) la página arrojaba un error 500 al iniciar.
4. **Peticiones HTTP redundantes en bucle (Agricultor):**
   * En `Agricultor.html`, al guardar múltiples actividades programadas se ejecutaba un ciclo `for` con múltiples peticiones fetch consecutivas, provocando parpadeo de pantalla y sobrecarga innecesaria en el servidor.
5. **Falta de sincronización en tiempo real entre paneles:**
   * Cuando un agricultor cosechaba o un transportista entregaba, los clientes y administradores no veían los cambios a menos que recargaran la página manualmente con F5.
6. **Detalles de usabilidad y nombres fijos:**
   * En `huerto360.html` se mostraba de forma estática `¡Buenos días, Betzy!` en lugar del nombre del administrador conectado y saludo horario.
   * El botón flotante de salir era diminuto (`13px`) y se empalmaba con elementos superiores.

---

## 🚀 Mejoras y Optimizaciones Aplicadas en la Versión 0.0.3

### 1. Unificación y Perfeccionamiento de Base de Datos (`Huerto360.sql` y `SPs.sql`)
* **Esquema DDL 100% consistente (`Huerto360.sql`):**
  * Soporte nativo para el rol `admin` en la tabla `usuarios`.
  * Estados completos en `pedidos` (`Pendiente`, `En ruta`, `Entregada`, `No entregada`, `Cancelado`).
  * Integración de `zona` y `tarea_jornalero_id` en `tareas_huerto` para sincronización Admin-Jornalero.
  * Incorporación de **índices de rendimiento** (`INDEX`) en claves de búsqueda frecuente (`rol`, `correo`, `estado`, `fecha`, `usuario_id`).
  * Inserción limpia y segura del usuario administrador inicial (`admin@huerto360.com` / `admin123`).
* **Colección Maestra Unificada (`SPs.sql`):**
  * Se concentraron los **13 Procedimientos Almacenados** en un único script ordenado, con manejo transaccional (`START TRANSACTION`, `COMMIT`, `ROLLBACK`) y validaciones mediante `SIGNAL SQLSTATE '45000'`:
    1. `sp_guardar_parcela`
    2. `sp_registrar_cosecha_agricultor`
    3. `sp_registrar_cosecha_jornalero`
    4. `sp_registrar_jornada`
    5. `sp_gestionar_tarea_jornalero`
    6. `sp_crear_reporte_incidencia`
    7. `sp_agregar_carrito`
    8. `sp_modificar_carrito`
    9. `sp_procesar_pedido`
    10. `sp_cancelar_pedido`
    11. `sp_iniciar_entrega`
    12. `sp_confirmar_entrega`
    13. `sp_reportar_entrega_fallida`

---

### 2. Conexión Resiliente con Fallback Inteligente (`conecion.php`)
* Se programó un mecanismo de conexión que intenta primero la clave configurada (`admin234`) y, en caso de fallo, realiza fallback automático a contraseña vacía (`""`) o `root`. Esto garantiza que el proyecto funcione de inmediato en cualquier instalación de XAMPP sin necesidad de tocar código.

---

### 3. Seguridad HTTP y Limpieza Total de Código (`api/*.php`)
* **Seguridad en cabeceras HTTP (`api/_comun.php`):**
  * `X-Content-Type-Options: nosniff` (previene ataques de tipo MIME sniffing).
  * `X-Frame-Options: SAMEORIGIN` (mitiga ataques de Clickjacking).
  * `Referrer-Policy: strict-origin-when-cross-origin`.
  * `Cache-Control: no-store, no-cache, must-revalidate`.
* **Eliminación del 100% de código muerto:**
  * Se depuraron todos los bloques comentados obsoletos en `login.php`, `registro.php`, `cliente.php`, `agricultor.php`, `jornalero.php`, `transportista.php` y `huerto360.php`.
  * Verificación sintáctica con PHP CLI: 0 errores detectados.

---

### 4. Sincronización Reactiva 360° en Tiempo Real (`huerto360-api.js`)
* Se implementó `iniciarSincronizacion(callback, intervaloMs)`:
  * Sondeo periódico no invasivo en segundo plano cada 25 segundos.
  * Detección reactiva mediante `visibilitychange`: cuando el usuario regresa a la pestaña del navegador, el panel se actualiza al instante con los últimos datos de la base de datos (nuevas cosechas, stock, pedidos o incidencias).

---

### 5. Rendimiento y Procesamiento en Lote (`Agricultor.html`, `api/agricultor.php`)
* **Batch Processing de Actividades:** Al seleccionar múltiples actividades de la lista, el formulario ahora las envía agrupadas en un solo paquete JSON al backend, ejecutando una sola transacción en base de datos en lugar de peticiones en bucle.

---

### 6. Accesibilidad y Usabilidad para Adultos Mayores
* **Botón de Salir Ergonómico (`js/huerto360-api.js`):**
  * Se rediseñó el botón flotante "🚪 Salir" con tamaño de toque de al menos `44px` (pauta WCAG), tipografía en negrita de `15px`, confirmación de salida y ubicación flotante inferior derecha que no obstaculiza encabezados ni menús.
* **Navegación Asistida fuera de jornada (`Jornalero.html`):**
  * El aviso de bloqueo fuera de turno ahora incluye un botón de acción rápida `"👉 Iniciar mi jornada"` que lleva al trabajador directo al registro de entrada.
* **Transparencia en Catálogo (`cliente.html`):**
  * Los productos con stock agotado muestran distintivo visual claro `⚠️ Agotado` y el botón queda inhabilitado con el texto `"Sin disponibilidad"`.
* **Saludo Dinámico y Reportes 360° (`huerto360.html`):**
  * Saludo personalizado según la hora del día y el nombre del usuario administrador conectado.
  * Inclusión del resumen de entregas de transportistas y reportes de campo de jornaleros en el panel de control.

---

## 🗂️ Estructura del Proyecto (Versión 0.0.3)

```text
proyecto_richi v0.0.3/
├── index.html              # Login y registro con checklist de seguridad en tiempo real
├── huerto360.html          # Panel del Administrador (monitoreo 360° con saludo dinámico)
├── Agricultor.html         # Panel del Agricultor (parcelas, tareas en lote y cosechas)
├── Jornalero.html          # Panel del Jornalero (jornadas, tareas, cosechas e incidencias)
├── cliente.html            # Panel del Cliente (catálogo con badges, carrito y pedidos)
├── Trasportista.html       # Panel del Transportista (rutas, entregas e incidencias)
├── conecion.php            # Conexión PDO resiliente con fallback inteligente
├── Huerto360.sql           # Base de datos completa, índices y datos iniciales
├── SPs.sql                 # Colección maestra de los 13 procedimientos almacenados
├── js/
│   └── huerto360-api.js    # Cliente API, botón accesible y sincronización en tiempo real
└── api/
    ├── _comun.php          # Sesiones, seguridad HTTP y respuestas JSON estandarizadas
    ├── login.php           # Autenticación segura y auto-creación de admin
    ├── registro.php        # Registro público validado
    ├── logout.php          # Destrucción segura de sesión y cookies
    ├── sesion.php          # Verificación de usuario activo
    ├── huerto360.php       # Endpoints limpios del Administrador
    ├── agricultor.php      # Endpoints del Agricultor (con soporte de lote)
    ├── jornalero.php       # Endpoints del Jornalero (control de jornada activa)
    ├── cliente.php         # Endpoints del Cliente
    └── transportista.php   # Endpoints del Transportista
```

---

## ⚙️ Instrucciones de Puesta en Marcha
1. **Importar la Base de Datos:**
   * Abre **phpMyAdmin** o **MySQL Workbench**.
   * Ejecuta en orden:
     1. `Huerto360.sql`
     2. `SPs.sql`
2. **Servidor Web:** Inicia el módulo **Apache** y **MySQL** desde el panel de control de **XAMPP**.
3. **Acceso:** Abre en tu navegador `http://localhost/proyecto_richi%20v0.0.3/index.html` (o la ruta correspondiente en tu carpeta `htdocs`).
4. **Credenciales Administrador:** `admin@huerto360.com` / `admin123`.

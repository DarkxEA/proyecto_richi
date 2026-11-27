# 🌻 HUERTO360 — Documentación de Cambios y Mejoras

Sistema web de gestión agrícola integral diseñado con enfoque de **accesibilidad para adultos mayores**, control de roles y sincronización automatizada entre módulos mediante **PHP + MySQL/MariaDB**.

---

## 📋 Resumen de Modificaciones Realizadas

### 1. Control de Acceso y Seguridad (`index.html`, `api/login.php`, `api/registro.php`)
* **Nuevo rol exclusivo de Administrador (`admin`):**
  * Se habilitó el rol `admin` en la base de datos con acceso exclusivo al panel general (`huerto360.html`).
  * El registro público quedó restringido únicamente a roles operativos (`agricultor`, `cliente`, `jornalero`, `trasportista`) para evitar registros no autorizados como administrador.
  * Creación automática de credenciales iniciales del administrador (`admin@huerto360.com` / `admin123`) con actualización segura de hash en `api/login.php`.
* **Validación de contraseñas accesible en tiempo real:**
  * Se implementó un checklist visual en el registro (`index.html`) pensado para personas mayores, mostrando en **verde (`✓`)** los requisitos cumplidos y en **rojo (`✗`)** los faltantes (mínimo 8 caracteres, una mayúscula, una minúscula y un número), además de verificación en vivo de coincidencia de contraseña.
  * Validación paralela en el backend (`api/registro.php`) para garantizar integridad de datos.

---

### 2. Accesibilidad para Adultos Mayores (`Agricultor.html`, `Jornalero.html`, `Trasportista.html`)
* **Tipografía ampliada:** Se incrementó el tamaño base de lectura a `17px` en los paneles operativos para mejorar la legibilidad.
* **Sustitución de campos de texto libre por Checklists:**
  * **Agricultor:** Selección mediante botones/casillas grandes (`22px`) con iconos para elegir cultivos, actividades programadas y observaciones de calidad en cosechas.
  * **Jornalero:** Selección visual por iconos para cultivos cosechados y hallazgos en reportes de incidencias en campo.

---

### 3. Reglas de Negocio y Bloqueo por Jornada (`Jornalero.html`, `api/jornalero.php`)
* **Modo Solo Consulta fuera de jornada:**
  * Antes de registrar entrada o después de registrar salida, el sistema bloquea cualquier acción operativa (iniciar/completar tareas, registrar cosechas o reportar incidencias).
  * El jornalero puede navegar y consultar todas sus secciones con un aviso claro en pantalla indicando el estado de su jornada.
  * La restricción está aplicada en las **3 capas**: interfaz (`Jornalero.html`), API (`api/jornalero.php`) y base de datos (`MySQL`).

---

### 4. Sincronización Entre Módulos y Base de Datos (`MySQL / MariaDB`)
* **Procedimientos Almacenados (`sp_`):** Se migró la lógica crítica a procedimientos almacenados con transacciones (`START TRANSACTION` / `ROLLBACK`) y validaciones mediante `SIGNAL SQLSTATE '45000'`:
  * `sp_guardar_parcela`: Validación de superficie, fechas y propiedad de parcelas.
  * `sp_registrar_cosecha_agricultor` y `sp_registrar_cosecha_jornalero`: Registran la cosecha y **suman automáticamente los kilogramos disponibles** al catálogo de productos del Cliente.
  * `sp_registrar_jornada`: Control de entrada y salida diaria sin duplicados.
  * `sp_gestionar_tarea_jornalero`: Gestión de tareas dentro de jornada activa y sincronización automática con el tablero del Administrador (`tareas_huerto`).
  * `sp_crear_reporte_incidencia`: Registro de incidencias en campo visibles desde el panel del Administrador.
  * `sp_procesar_pedido`, `sp_iniciar_entrega`, `sp_confirmar_entrega` y `sp_reportar_entrega_fallida`: Flujo completo de compras del Cliente con descuento de stock, generación de entregas y sincronización en tiempo real del estado del pedido (`Pendiente` $\rightarrow$ `En ruta` $\rightarrow$ `Entregada` / `No entregada`).
* **Limpieza de código en Backend (`api/*.php`):** Se eliminaron etiquetas duplicadas (`<?php`) y bloques comentados residuales para evitar errores de sintaxis en Apache/PHP.

---

## 🗂️ Estructura Principal del Proyecto

```text
proyecto_richi/
├── index.html              # Inicio de sesión y registro con checklist de seguridad
├── huerto360.html          # Panel del Administrador (control general y monitoreo 360°)
├── Agricultor.html         # Panel del Agricultor (parcelas, actividades y cosechas)
├── Jornalero.html          # Panel del Jornalero (jornada, tareas, cosechas e incidencias)
├── cliente.html            # Panel del Cliente (catálogo, carrito y seguimiento de pedidos)
├── Trasportista.html       # Panel del Transportista (rutas, entregas e incidencias)
├── conecion.php            # Conexión PDO a MySQL/MariaDB
├── js/
│   └── huerto360-api.js    # Cliente fetch centralizado y control de sesión
└── api/
    ├── _comun.php          # Manejo de sesiones, roles y respuestas JSON
    ├── login.php           # Autenticación e inicialización de admin
    ├── registro.php        # Registro público validado
    ├── logout.php          # Cierre de sesión
    ├── sesion.php          # Verificación de sesión activa
    ├── huerto360.php       # Endpoints del Administrador
    ├── agricultor.php      # Endpoints del Agricultor
    ├── jornalero.php       # Endpoints del Jornalero (con validación de jornada)
    ├── cliente.php         # Endpoints del Cliente
    └── transportista.php   # Endpoints del Transportista
```

---

## ⚙️ Requisitos de Ejecución Local
1. **Servidor Web:** Apache encendido desde el panel de control de **XAMPP**.
2. **Base de Datos:** Servicio **MySQL Server 8.0+** activo (administrado vía **MySQL Workbench**) con la base `Huerto360` y sus procedimientos almacenados ejecutados.
3. **Acceso:** Abrir en el navegador `http://localhost/proyecto_richi/index.html`.
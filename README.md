# Huerto360 🥦🌱

Sistema web de gestión agrícola integral para huertos y comercialización, con roles diferenciados para **Agricultores**, **Clientes**, **Jornaleros** y **Transportistas**.

## 🚀 Tecnologías utilizadas
- **Frontend:** HTML5, CSS3, JavaScript (Vanilla ES6+).
- **Backend:** PHP 8.x (APIs RESTful con PDO y sesiones nativas).
- **Base de datos:** MySQL / MariaDB (motor InnoDB).

## 📁 Estructura del proyecto
- `index.html`: Portal principal con inicio de sesión y registro de usuarios por rol.
- `huerto360.html`: Panel general del huerto (cultivos, zonas de riego, sensores).
- `Agricultor.html`: Panel de control de parcelas, cosechas y jornadas para agricultores.
- `cliente.html`: Tienda virtual, catálogo de hortalizas, carrito y gestión de pedidos.
- `Jornalero.html`: Bitácora de campo y tareas diarias asignadas.
- `Trasportista.html`: Gestión de entregas, rutas y reporte de incidencias.
- `api/`: Endpoints PHP para cada módulo y autenticación.
- `conecion.php`: Archivo de conexión PDO a MySQL.
- `Huerto360.sql`: Esquema de base de datos con tablas y datos de prueba.

## 🛠️ Instalación y ejecución local con XAMPP

1. **Copiar el proyecto:**
   Coloca la carpeta `proyecto_richi` dentro del directorio `htdocs` de XAMPP:
   ```text
   C:\xampp\htdocs\proyecto_richi
   ```

2. **Iniciar servicios:**
   Abre el Panel de Control de XAMPP y arranca los módulos **Apache** y **MySQL**.

3. **Importar la base de datos:**
   - Abre tu navegador en [http://localhost/phpmyadmin](http://localhost/phpmyadmin).
   - Ve a la pestaña **Importar**.
   - Selecciona el archivo `Huerto360.sql` y presiona **Importar**.

4. **Acceder al sistema:**
   Ingresa desde tu navegador a:
   [http://localhost/proyecto_richi/](http://localhost/proyecto_richi/)

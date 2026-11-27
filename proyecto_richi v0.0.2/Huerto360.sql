-- =====================================================================
--  Huerto360 · Script de base de datos (MySQL / MariaDB, XAMPP)
--  Coincide con conecion.php  →  BD: Huerto360 · usuario: root · sin contraseña
--  Importar en phpMyAdmin (pestaña "Importar") o:  mysql -u root < Huerto360.sql
-- =====================================================================

CREATE DATABASE IF NOT EXISTS Huerto360
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE Huerto360;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS incidencias, entregas, pedido_items, pedidos, carrito_items, productos,
  reportes, jornadas, cosechas, tareas_jornalero, tareas_parcela, parcelas,
  inventario, eventos, tareas_huerto, zonas, cultivos, usuarios;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
--  USUARIOS  (index.html: registro y login)
--  Campos del registro: regNombre, regRol, regCorreo, regContrasena
--  telefono/direccion se usan en el perfil del cliente (cliente.html)
--  contrasena guarda el HASH: password_hash() al registrar, password_verify() al entrar
-- ---------------------------------------------------------------------
CREATE TABLE usuarios (
  id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre         VARCHAR(100) NOT NULL,
  rol            ENUM('agricultor','cliente','jornalero','trasportista') NOT NULL,
  correo         VARCHAR(150) NOT NULL UNIQUE,
  contrasena     VARCHAR(255) NOT NULL,
  telefono       VARCHAR(20)  NULL,
  direccion      TEXT         NULL,
  fecha_registro DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  huerto360.html  (panel general)
-- ---------------------------------------------------------------------
CREATE TABLE cultivos (
  id     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(80) NOT NULL,
  icono  VARCHAR(10) NOT NULL DEFAULT '🌱',
  salud  TINYINT UNSIGNED NOT NULL DEFAULT 100,           -- 0 a 100
  CONSTRAINT chk_salud CHECK (salud BETWEEN 0 AND 100)
) ENGINE=InnoDB;

CREATE TABLE zonas (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre     VARCHAR(80) NOT NULL UNIQUE,
  humedad    TINYINT UNSIGNED NOT NULL DEFAULT 50,        -- 0 a 100
  riego_auto TINYINT(1) NOT NULL DEFAULT 0,
  CONSTRAINT chk_humedad CHECK (humedad BETWEEN 0 AND 100)
) ENGINE=InnoDB;

CREATE TABLE tareas_huerto (
  id      INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  texto   VARCHAR(200) NOT NULL,
  fecha   DATE NOT NULL,
  minutos SMALLINT UNSIGNED NOT NULL DEFAULT 10,          -- 10, 15, 20, 25
  hecha   TINYINT(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB;

CREATE TABLE eventos (
  id    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  fecha DATE NOT NULL,
  texto VARCHAR(200) NOT NULL
) ENGINE=InnoDB;

CREATE TABLE inventario (
  id       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre   VARCHAR(100) NOT NULL,
  cantidad DECIMAL(10,2) NOT NULL DEFAULT 0
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  Agricultor.html
-- ---------------------------------------------------------------------
CREATE TABLE parcelas (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  usuario_id    INT UNSIGNED NULL,                        -- agricultor dueño
  nombre        VARCHAR(100) NOT NULL,
  cultivo       VARCHAR(80)  NOT NULL,
  area_m2       DECIMAL(10,2) NOT NULL,
  fecha_siembra DATE NOT NULL,
  etapa         ENUM('Siembra','Crecimiento','Floración','Cosecha','Finalizado')
                NOT NULL DEFAULT 'Siembra',
  CONSTRAINT fk_parcela_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE tareas_parcela (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  parcela_id INT UNSIGNED NOT NULL,
  nombre     VARCHAR(200) NOT NULL,
  fecha      DATE NOT NULL,
  completada TINYINT(1) NOT NULL DEFAULT 0,
  CONSTRAINT fk_tarea_parcela FOREIGN KEY (parcela_id)
    REFERENCES parcelas(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  COSECHAS  (las registran el Agricultor: parcela, kg, fecha, notas
--             y el Jornalero: cultivo, zona, cantidad, fecha)
-- ---------------------------------------------------------------------
CREATE TABLE cosechas (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  usuario_id INT UNSIGNED NULL,
  parcela_id INT UNSIGNED NULL,                           -- si viene del Agricultor
  cultivo    VARCHAR(80) NULL,                            -- si viene del Jornalero
  zona       VARCHAR(80) NULL,                            -- si viene del Jornalero
  kg         DECIMAL(10,2) NOT NULL,
  fecha      DATE NOT NULL,
  notas      TEXT NULL,
  CONSTRAINT chk_kg CHECK (kg > 0),
  CONSTRAINT fk_cosecha_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios(id) ON DELETE SET NULL,
  CONSTRAINT fk_cosecha_parcela FOREIGN KEY (parcela_id)
    REFERENCES parcelas(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  Jornalero.html
-- ---------------------------------------------------------------------
CREATE TABLE tareas_jornalero (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  usuario_id INT UNSIGNED NULL,
  nombre     VARCHAR(200) NOT NULL,
  zona       ENUM('Invernadero','Exterior','Huerto norte') NOT NULL,
  fecha      DATE NOT NULL,
  estado     ENUM('Pendiente','En proceso','Completada') NOT NULL DEFAULT 'Pendiente',
  CONSTRAINT fk_tj_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- Entrada / salida de la jornada (checkIn / checkOut)
CREATE TABLE jornadas (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  usuario_id INT UNSIGNED NULL,
  inicio     DATETIME NOT NULL,
  fin        DATETIME NULL,
  CONSTRAINT fk_jornada_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE reportes (
  id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  usuario_id  INT UNSIGNED NULL,
  tipo        ENUM('Plaga','Falta de agua','Herramienta dañada','Otro') NOT NULL,
  zona        ENUM('Invernadero','Exterior','Huerto norte') NOT NULL,
  descripcion TEXT NOT NULL,
  fecha       DATE NOT NULL,
  CONSTRAINT fk_reporte_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  cliente.html  (catálogo, carrito en el navegador, pedidos)
-- ---------------------------------------------------------------------
CREATE TABLE productos (
  id     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(80) NOT NULL UNIQUE,
  icono  VARCHAR(10) NOT NULL DEFAULT '🌱',
  precio INT UNSIGNED NOT NULL,                           -- en CENTAVOS: 2800 = $28.00 por kg
  stock  INT UNSIGNED NOT NULL DEFAULT 0                  -- kg disponibles
) ENGINE=InnoDB;

-- Carrito de cada cliente (en cliente.html se guardaba en localStorage)
CREATE TABLE carrito_items (
  usuario_id  INT UNSIGNED NOT NULL,
  producto_id INT UNSIGNED NOT NULL,
  cantidad    INT UNSIGNED NOT NULL,
  PRIMARY KEY (usuario_id, producto_id),
  CONSTRAINT chk_carrito_cantidad CHECK (cantidad > 0),
  CONSTRAINT fk_carrito_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios(id) ON DELETE CASCADE,
  CONSTRAINT fk_carrito_producto FOREIGN KEY (producto_id)
    REFERENCES productos(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE pedidos (
  numero         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  usuario_id     INT UNSIGNED NULL,
  cliente_nombre VARCHAR(100) NOT NULL,
  telefono       VARCHAR(20)  NOT NULL,
  direccion      TEXT NOT NULL,
  total          INT UNSIGNED NOT NULL,                   -- en centavos
  estado         ENUM('Pendiente','Cancelado') NOT NULL DEFAULT 'Pendiente',
  creado_en      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_pedido_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE pedido_items (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  pedido_numero INT UNSIGNED NOT NULL,
  producto_id   INT UNSIGNED NULL,
  nombre        VARCHAR(80) NOT NULL,                     -- copia del nombre al momento de comprar
  precio        INT UNSIGNED NOT NULL,                    -- centavos, copia del precio al comprar
  cantidad      INT UNSIGNED NOT NULL,
  CONSTRAINT chk_cantidad CHECK (cantidad > 0),
  CONSTRAINT fk_item_pedido FOREIGN KEY (pedido_numero)
    REFERENCES pedidos(numero) ON DELETE CASCADE,
  CONSTRAINT fk_item_producto FOREIGN KEY (producto_id)
    REFERENCES productos(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  Trasportista.html
-- ---------------------------------------------------------------------
CREATE TABLE entregas (
  id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  transportista_id INT UNSIGNED NULL,
  pedido_numero  INT UNSIGNED NULL,                       -- opcional: liga con cliente.html
  cliente        VARCHAR(100) NOT NULL,
  direccion      VARCHAR(255) NOT NULL,
  cultivo        VARCHAR(80)  NOT NULL,
  cantidad       DECIMAL(10,2) NOT NULL,
  fecha          DATE NOT NULL,
  estado         ENUM('Pendiente','En ruta','Entregada','No entregada')
                 NOT NULL DEFAULT 'Pendiente',
  nota           TEXT NULL,                               -- motivo si no se entregó
  entregada_en   DATETIME NULL,
  CONSTRAINT fk_entrega_usuario FOREIGN KEY (transportista_id)
    REFERENCES usuarios(id) ON DELETE SET NULL,
  CONSTRAINT fk_entrega_pedido FOREIGN KEY (pedido_numero)
    REFERENCES pedidos(numero) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE incidencias (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  entrega_id INT UNSIGNED NOT NULL,
  tipo       ENUM('Retraso','Vehículo','Producto dañado','Dirección incorrecta','Otro') NOT NULL,
  detalles   TEXT NOT NULL,
  creada_en  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_incidencia_entrega FOREIGN KEY (entrega_id)
    REFERENCES entregas(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- =====================================================================
--  DATOS INICIALES (los mismos que cada HTML trae por defecto)
-- =====================================================================
INSERT INTO cultivos (nombre, icono, salud) VALUES
  ('Tomate','🍅',85), ('Lechuga','🥬',72), ('Zanahoria','🥕',91), ('Maíz','🌽',64);

INSERT INTO zonas (nombre, humedad, riego_auto) VALUES
  ('Invernadero',85,0), ('Exterior',72,1), ('Huerto norte',61,0);

INSERT INTO tareas_huerto (texto, fecha, minutos) VALUES
  ('Revisar humedad de Zona 3', CURDATE(), 10),
  ('Cosechar lechuga madura', CURDATE(), 15),
  ('Preparar fertilizante orgánico', CURDATE(), 20);

INSERT INTO eventos (fecha, texto) VALUES (CURDATE(), 'Revisión de riego');

INSERT INTO tareas_jornalero (nombre, zona, fecha) VALUES
  ('Revisar humedad de Zona 1','Invernadero',CURDATE()),
  ('Deshierbar área de lechugas','Exterior',CURDATE()),
  ('Revisar hojas de zanahoria','Huerto norte',CURDATE());

INSERT INTO productos (nombre, icono, precio, stock) VALUES
  ('Tomate','🍅',2800,50), ('Lechuga','🥬',2200,35),
  ('Zanahoria','🥕',1800,40), ('Maíz','🌽',2500,60);

INSERT INTO entregas (cliente, direccion, cultivo, cantidad, fecha) VALUES
  ('Mercado Central','Av. Juárez 120, Mixquiahuala, Hidalgo','Lechuga',40,CURDATE()),
  ('Restaurante El Huerto','Calle Morelos 45, Mixquiahuala, Hidalgo','Zanahoria',25,CURDATE()),
  ('Tienda La Cosecha','Centro, Progreso de Obregón, Hidalgo','Tomate',30,CURDATE());

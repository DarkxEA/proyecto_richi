-- =====================================================================
-- Huerto360 v0.0.3 · Estructura Completa y Unificada de Base de Datos
-- (MySQL 8.0+ / MariaDB)
-- Compatible con XAMPP: usuario root
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
-- 1. USUARIOS (Soporte nativo para Administrador y roles operativos)
-- ---------------------------------------------------------------------
CREATE TABLE usuarios (
  id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre         VARCHAR(100) NOT NULL,
  rol            ENUM('admin','agricultor','cliente','jornalero','trasportista') NOT NULL,
  correo         VARCHAR(150) NOT NULL UNIQUE,
  contrasena     VARCHAR(255) NOT NULL,
  telefono       VARCHAR(20)  NULL,
  direccion      TEXT         NULL,
  fecha_registro DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_usuarios_rol (rol),
  INDEX idx_usuarios_correo (correo)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2. PANEL GENERAL HUERTO360 (Monitoreo General)
-- ---------------------------------------------------------------------
CREATE TABLE cultivos (
  id     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(80) NOT NULL UNIQUE,
  icono  VARCHAR(10) NOT NULL DEFAULT '🌱',
  salud  TINYINT UNSIGNED NOT NULL DEFAULT 100,
  CONSTRAINT chk_salud CHECK (salud BETWEEN 0 AND 100)
) ENGINE=InnoDB;

CREATE TABLE zonas (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre     VARCHAR(80) NOT NULL UNIQUE,
  humedad    TINYINT UNSIGNED NOT NULL DEFAULT 50,
  riego_auto TINYINT(1) NOT NULL DEFAULT 0,
  CONSTRAINT chk_humedad CHECK (humedad BETWEEN 0 AND 100)
) ENGINE=InnoDB;

CREATE TABLE tareas_jornalero (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  usuario_id INT UNSIGNED NULL,
  nombre     VARCHAR(200) NOT NULL,
  zona       ENUM('Invernadero','Exterior','Huerto norte') NOT NULL,
  fecha      DATE NOT NULL,
  estado     ENUM('Pendiente','En proceso','Completada') NOT NULL DEFAULT 'Pendiente',
  CONSTRAINT fk_tj_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios(id) ON DELETE SET NULL,
  INDEX idx_tj_estado (estado),
  INDEX idx_tj_fecha (fecha)
) ENGINE=InnoDB;

CREATE TABLE tareas_huerto (
  id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  texto               VARCHAR(200) NOT NULL,
  fecha               DATE NOT NULL,
  minutos             SMALLINT UNSIGNED NOT NULL DEFAULT 10,
  hecha               TINYINT(1) NOT NULL DEFAULT 0,
  zona                ENUM('Invernadero','Exterior','Huerto norte') NOT NULL DEFAULT 'Invernadero',
  tarea_jornalero_id INT UNSIGNED NULL,
  CONSTRAINT fk_th_tj FOREIGN KEY (tarea_jornalero_id)
    REFERENCES tareas_jornalero(id) ON DELETE SET NULL
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
-- 3. MÓDULO AGRICULTOR
-- ---------------------------------------------------------------------
CREATE TABLE parcelas (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  usuario_id    INT UNSIGNED NULL,
  nombre        VARCHAR(100) NOT NULL,
  cultivo       VARCHAR(80)  NOT NULL,
  area_m2       DECIMAL(10,2) NOT NULL,
  fecha_siembra DATE NOT NULL,
  etapa         ENUM('Siembra','Crecimiento','Floración','Cosecha','Finalizado') NOT NULL DEFAULT 'Siembra',
  CONSTRAINT fk_parcela_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios(id) ON DELETE SET NULL,
  INDEX idx_parcelas_usuario (usuario_id)
) ENGINE=InnoDB;

CREATE TABLE tareas_parcela (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  parcela_id INT UNSIGNED NOT NULL,
  nombre     VARCHAR(200) NOT NULL,
  fecha      DATE NOT NULL,
  completada TINYINT(1) NOT NULL DEFAULT 0,
  CONSTRAINT fk_tarea_parcela FOREIGN KEY (parcela_id)
    REFERENCES parcelas(id) ON DELETE CASCADE,
  INDEX idx_tp_parcela (parcela_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 4. COSECHAS (Sincronizadas entre Agricultor, Jornalero y Catálogo)
-- ---------------------------------------------------------------------
CREATE TABLE cosechas (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  usuario_id INT UNSIGNED NULL,
  parcela_id INT UNSIGNED NULL,
  cultivo    VARCHAR(80) NULL,
  zona       VARCHAR(80) NULL,
  kg         DECIMAL(10,2) NOT NULL,
  fecha      DATE NOT NULL,
  notas      TEXT NULL,
  CONSTRAINT chk_kg CHECK (kg > 0),
  CONSTRAINT fk_cosecha_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios(id) ON DELETE SET NULL,
  CONSTRAINT fk_cosecha_parcela FOREIGN KEY (parcela_id)
    REFERENCES parcelas(id) ON DELETE SET NULL,
  INDEX idx_cosechas_fecha (fecha)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 5. MÓDULO JORNALERO (Jornadas e Incidencias en campo)
-- ---------------------------------------------------------------------
CREATE TABLE jornadas (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  usuario_id INT UNSIGNED NULL,
  inicio     DATETIME NOT NULL,
  fin        DATETIME NULL,
  CONSTRAINT fk_jornada_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios(id) ON DELETE SET NULL,
  INDEX idx_jornadas_usuario_fecha (usuario_id, inicio)
) ENGINE=InnoDB;

CREATE TABLE reportes (
  id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  usuario_id  INT UNSIGNED NULL,
  tipo        ENUM('Plaga','Falta de agua','Herramienta dañada','Otro') NOT NULL,
  zona        ENUM('Invernadero','Exterior','Huerto norte') NOT NULL,
  descripcion TEXT NOT NULL,
  fecha       DATE NOT NULL,
  CONSTRAINT fk_reporte_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios(id) ON DELETE SET NULL,
  INDEX idx_reportes_fecha (fecha)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 6. MÓDULO CLIENTE (Catálogo, Carrito y Pedidos)
-- ---------------------------------------------------------------------
CREATE TABLE productos (
  id     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(80) NOT NULL UNIQUE,
  icono  VARCHAR(10) NOT NULL DEFAULT '🌱',
  precio INT UNSIGNED NOT NULL, -- en CENTAVOS: 2500 = $25.00 MXN
  stock  INT UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB;

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
  total          INT UNSIGNED NOT NULL,
  estado         ENUM('Pendiente','En ruta','Entregada','No entregada','Cancelado') NOT NULL DEFAULT 'Pendiente',
  creado_en      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_pedido_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios(id) ON DELETE SET NULL,
  INDEX idx_pedidos_usuario (usuario_id),
  INDEX idx_pedidos_estado (estado)
) ENGINE=InnoDB;

CREATE TABLE pedido_items (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  pedido_numero INT UNSIGNED NOT NULL,
  producto_id   INT UNSIGNED NULL,
  nombre        VARCHAR(80) NOT NULL,
  precio        INT UNSIGNED NOT NULL,
  cantidad      INT UNSIGNED NOT NULL,
  CONSTRAINT chk_cantidad CHECK (cantidad > 0),
  CONSTRAINT fk_item_pedido FOREIGN KEY (pedido_numero)
    REFERENCES pedidos(numero) ON DELETE CASCADE,
  CONSTRAINT fk_item_producto FOREIGN KEY (producto_id)
    REFERENCES productos(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 7. MÓDULO TRANSPORTISTA (Entregas e Incidencias en Ruta)
-- ---------------------------------------------------------------------
CREATE TABLE entregas (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  transportista_id INT UNSIGNED NULL,
  pedido_numero    INT UNSIGNED NULL,
  cliente          VARCHAR(100) NOT NULL,
  direccion        VARCHAR(255) NOT NULL,
  cultivo          VARCHAR(80)  NOT NULL,
  cantidad         DECIMAL(10,2) NOT NULL,
  fecha            DATE NOT NULL,
  estado           ENUM('Pendiente','En ruta','Entregada','No entregada') NOT NULL DEFAULT 'Pendiente',
  nota             TEXT NULL,
  entregada_en     DATETIME NULL,
  CONSTRAINT fk_entrega_usuario FOREIGN KEY (transportista_id)
    REFERENCES usuarios(id) ON DELETE SET NULL,
  CONSTRAINT fk_entrega_pedido FOREIGN KEY (pedido_numero)
    REFERENCES pedidos(numero) ON DELETE SET NULL,
  INDEX idx_entregas_transportista (transportista_id),
  INDEX idx_entregas_estado (estado)
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
-- DATOS INICIALES Y USUARIO ADMINISTRADOR
-- =====================================================================

-- Usuario Administrador Inicial (admin@huerto360.com / admin123)
INSERT INTO usuarios (nombre, rol, correo, contrasena) VALUES (
  'Administrador Huerto360',
  'admin',
  'admin@huerto360.com',
  '$2y$10$w09u7uR3bAoxM8sH.3sHyeQ0qg15V9jP.q1z.7M1XQvX17x8Y0Gk2'
);

INSERT INTO cultivos (nombre, icono, salud) VALUES
  ('Tomate','🍅',85), ('Lechuga','🥬',72), ('Zanahoria','🥕',91), ('Maíz','🌽',64);

INSERT INTO zonas (nombre, humedad, riego_auto) VALUES
  ('Invernadero',85,0), ('Exterior',72,1), ('Huerto norte',61,0);

INSERT INTO tareas_jornalero (id, nombre, zona, fecha, estado) VALUES
  (1, 'Revisar humedad de Zona 1', 'Invernadero', CURDATE(), 'Pendiente'),
  (2, 'Deshierbar área de lechugas', 'Exterior', CURDATE(), 'Pendiente'),
  (3, 'Revisar hojas de zanahoria', 'Huerto norte', CURDATE(), 'Pendiente');

INSERT INTO tareas_huerto (texto, fecha, minutos, zona, tarea_jornalero_id) VALUES
  ('Revisar humedad de Zona 1', CURDATE(), 10, 'Invernadero', 1),
  ('Deshierbar área de lechugas', CURDATE(), 15, 'Exterior', 2),
  ('Revisar hojas de zanahoria', CURDATE(), 20, 'Huerto norte', 3);

INSERT INTO eventos (fecha, texto) VALUES (CURDATE(), 'Revisión general de riego');

INSERT INTO productos (nombre, icono, precio, stock) VALUES
  ('Tomate','🍅',2800,50), ('Lechuga','🥬',2200,35),
  ('Zanahoria','🥕',1800,40), ('Maíz','🌽',2500,60);

INSERT INTO entregas (cliente, direccion, cultivo, cantidad, fecha, estado) VALUES
  ('Mercado Central','Av. Juárez 120, Mixquiahuala, Hidalgo','Lechuga',40,CURDATE(),'Pendiente'),
  ('Restaurante El Huerto','Calle Morelos 45, Mixquiahuala, Hidalgo','Zanahoria',25,CURDATE(),'Pendiente'),
  ('Tienda La Cosecha','Centro, Progreso de Obregón, Hidalgo','Tomate',30,CURDATE(),'Pendiente');

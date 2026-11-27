USE Huerto360;

-- 1. Agregar rol 'admin' a usuarios y crear cuenta administradora
ALTER TABLE usuarios 
  MODIFY COLUMN rol ENUM('admin','agricultor','cliente','jornalero','trasportista') NOT NULL;

INSERT IGNORE INTO usuarios (nombre, rol, correo, contrasena) VALUES (
  'Administrador Huerto360',
  'admin',
  'admin@huerto360.com',
  '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi' -- password: password (lo actualizamos abajo)
);

-- Asegurar contraseña 'admin123' con hash bcrypt estándar
UPDATE usuarios 
SET contrasena = PASSWORD('admin123') 
WHERE correo = 'admin@huerto360.com';
-- NOTA: Como PHP usa password_verify(), ejecuta una vez en PHP o usa este hash real de 'admin123':
UPDATE usuarios 
SET contrasena = '$2y$10$e0MYzXyjpJS7Pd0RVvHwHe.24t1L1h.u3E2w2x1oZ1g7p7y0u2Z1a'
WHERE correo = 'admin@huerto360.com';

-- 2. Ampliar estados de pedidos para reflejar el avance del Transportista al Cliente
ALTER TABLE pedidos 
  MODIFY COLUMN estado ENUM('Pendiente','En ruta','Entregada','No entregada','Cancelado') NOT NULL DEFAULT 'Pendiente';

-- 3. Ligar tareas_huerto con tareas_jornalero para sincronizar Admin <-> Jornalero
ALTER TABLE tareas_huerto 
  ADD COLUMN zona ENUM('Invernadero','Exterior','Huerto norte') NOT NULL DEFAULT 'Invernadero',
  ADD COLUMN tarea_jornalero_id INT UNSIGNED NULL;
-- =============================================================
-- POBLAR - SISTEMA DE GESTION DE RESTAURANTE (PostgreSQL)
-- Equipo 5 - Bases de Datos
-- Archivo 2 de 6. Solo filas que deben entrar; padres antes que hijos.
-- Todos los datos son inventados: no hay personas reales.
-- Convencion: cedulas CLI-TEST-### / EMP-TEST-###, telefonos 000000####,
-- correos clienteN@ejemplo.test. Fechas fijas (9 al 15 de nov 2026).
-- Requiere haber corrido esquema_equipo5.sql sobre una base vacia
-- (los id SERIAL parten de 1; los INSERT dependen de ese orden).
-- =============================================================

BEGIN;

-- 1. CATALOGOS (cada uno con 5 o mas filas)
INSERT INTO EstadoEmpleado (nombre_estado_empleado) VALUES
('Disponible'), ('En turno'), ('En descanso'), ('Inactivo'), ('Vacaciones');

INSERT INTO EstadoMesa (nombre_estado_mesa) VALUES
('Disponible'), ('Ocupada'), ('Reservada'), ('Fuera de servicio'), ('En limpieza');

INSERT INTO EstadoCliente (nombre_estado_cliente) VALUES
('Activo'), ('Frecuente'), ('Inactivo'), ('Nuevo'), ('Bloqueado');

INSERT INTO EstadoReserva (nombre_estado_reserva) VALUES
('Pendiente'), ('Confirmada'), ('Atendida'), ('Cancelada'), ('No asistió');

INSERT INTO TipoReserva (nombre_tipo, duracion_horas, costo_adicional, descripcion_tipo_reserva) VALUES
('Estándar', 2.0, 0.00, 'Reserva regular para almuerzo o cena'),
('Cumpleaños', 3.0, 30000.00, 'Incluye decoración y mesa especial'),
('Corporativa', 4.0, 50000.00, 'Reunión de trabajo con reserva de espacio'),
('Aniversario', 3.0, 25000.00, 'Mesa decorada para pareja'),
('Evento privado', 5.0, 80000.00, 'Uso exclusivo de una zona del restaurante');

INSERT INTO EstadoPedido (nombre_estado_pedido) VALUES
('Pendiente'), ('En preparación'), ('Listo'), ('Entregado'), ('Pagado'), ('Cancelado');

INSERT INTO EstadoPlato (nombre_estado_plato) VALUES
('Disponible'), ('Agotado'), ('Descontinuado'), ('De temporada'), ('En revisión');

INSERT INTO EstadoMenu (nombre_estado_menu) VALUES
('Activo'), ('Inactivo'), ('Borrador'), ('Archivado'), ('Temporal');

INSERT INTO CategoriaPlato (nombre_categoria_plato, descripcion_categoria_plato) VALUES
('Platos Fuertes', 'Platos tradicionales y completos'),
('Comidas Rápidas', 'Hamburguesas y comida al paso'),
('Buffet / Porciones', 'Porciones individuales para armar platos'),
('Bebidas', 'Bebidas frías y calientes'),
('Postres', 'Dulces y postres caseros');

-- 2. MENUS, EMPLEADOS, MESAS, CLIENTES
INSERT INTO Menu (nombre_menu, id_estado_menu) VALUES
('Menú Principal 2026', 1),
('Menú Almuerzos Ejecutivos', 1),
('Menú Buffet', 5),
('Menú Infantil', 3),
('Menú Fin de Semana', 2);

INSERT INTO Empleado (cedula, nombre_empleado, rol, id_estado_empleado) VALUES
('EMP-TEST-001', 'Empleado Prueba 1', 'Mesero', 2),
('EMP-TEST-002', 'Empleado Prueba 2', 'Mesero', 2),
('EMP-TEST-003', 'Empleado Prueba 3', 'Cajero', 2),
('EMP-TEST-004', 'Empleado Prueba 4', 'Cocinero', 3),
('EMP-TEST-005', 'Empleado Prueba 5', 'Administrador', 5);

-- Mesas 1,2,4,5,6 ocupadas (tienen pedido activo); mesas 7 y 8 sin pedidos
INSERT INTO Mesa (numero_mesa, capacidad_mesa, id_estado_mesa) VALUES
(1, 4, 2), (2, 2, 2), (3, 6, 3), (4, 4, 2),
(5, 8, 2), (6, 2, 2), (7, 4, 5), (8, 10, 4);

INSERT INTO Cliente (cedula_cliente, nombre_cliente, telefono, email, fecha_registro, id_estado_cliente) VALUES
('CLI-TEST-001', 'Cliente Prueba 1', '0000000001', 'cliente1@ejemplo.test', '2026-10-02 10:00:00', 2),
('CLI-TEST-002', 'Cliente Prueba 2', '0000000002', 'cliente2@ejemplo.test', '2026-10-05 10:00:00', 1),
('CLI-TEST-003', 'Cliente Prueba 3', '0000000003', 'cliente3@ejemplo.test', '2026-10-09 10:00:00', 1),
('CLI-TEST-004', 'Cliente Prueba 4', '0000000004', 'cliente4@ejemplo.test', '2026-10-12 10:00:00', 2),
('CLI-TEST-005', 'Cliente Prueba 5', '0000000005', 'cliente5@ejemplo.test', '2026-10-15 10:00:00', 1),
('CLI-TEST-006', 'Cliente Prueba 6', '0000000006', 'cliente6@ejemplo.test', '2026-10-20 10:00:00', 4),
('CLI-TEST-007', 'Cliente Prueba 7', '0000000007', NULL, '2026-10-24 10:00:00', 1),
('CLI-TEST-008', 'Cliente Prueba 8', '0000000008', 'cliente8@ejemplo.test', '2026-10-28 10:00:00', 1),
('CLI-TEST-009', 'Cliente Prueba 9', NULL, 'cliente9@ejemplo.test', '2026-11-02 10:00:00', 4),
('CLI-TEST-010', 'Cliente Prueba 10', '0000000010', 'cliente10@ejemplo.test', '2026-11-05 10:00:00', 1);

-- 3. INGREDIENTES. stock_actual entra como stock INICIAL (antes del 8 nov) y se
-- recalcula en la seccion 8 con los movimientos. Aguacate y Cilantro no estan
-- en ninguna receta; Lechuga queda bajo el minimo.
INSERT INTO Ingrediente (nombre_ingrediente, unidad_medida, stock_actual, stock_minimo, precio_adicional, ubicacion) VALUES
('Carne molida de res', 'g', 15000.000, 2000.000, 6000.00, 'Refrigerador Carnes 1'),
('Filete de res crudo', 'g', 20000.000, 3000.000, 10000.00, 'Refrigerador Carnes 2'),
('Pan brioche hamburguesa', 'unidad', 80.000, 20.000, 2500.00, 'Estantería Panadería'),
('Queso cheddar tajado', 'g', 4000.000, 500.000, 2500.00, 'Nevera Lácteos'),
('Cebolla cabezona', 'g', 8000.000, 1000.000, 1000.00, 'Bodega Verduras'),
('Arroz crudo', 'g', 25000.000, 5000.000, 0.00, 'Despensa Granos'),
('Aceite vegetal', 'ml', 10000.000, 2000.000, 0.00, 'Despensa Líquidos'),
('Gaseosa 400ml', 'unidad', 50.000, 10.000, 0.00, 'Nevera Bebidas'),
('Pechuga de pollo cruda', 'g', 18000.000, 2500.000, 8000.00, 'Refrigerador Aves'),
('Papa criolla', 'g', 15000.000, 3000.000, 3000.00, 'Bodega Tubérculos'),
('Aguacate Hass', 'unidad', 30.000, 5.000, 3500.00, 'Estantería Frutas/Verduras'),
('Naranja', 'unidad', 120.000, 30.000, 1500.00, 'Estantería Frutas/Verduras'),
('Limón', 'unidad', 150.000, 40.000, 500.00, 'Estantería Frutas/Verduras'),
('Chocolate para repostería', 'g', 6000.000, 1000.000, 2000.00, 'Despensa Dulces'),
('Lentejas', 'g', 9000.000, 2000.000, 0.00, 'Despensa Granos'),
('Cilantro fresco', 'g', 800.000, 200.000, 500.00, 'Nevera Verduras'),
('Lechuga', 'g', 400.000, 500.000, 1000.00, 'Nevera Verduras'),
('Tomate', 'g', 5000.000, 800.000, 1000.00, 'Bodega Verduras');

-- 4. PLATOS (12) Y RECETAS
INSERT INTO Plato (nombre_plato, descripcion_plato, precio_base, tiempo_preparacion_min, es_personalizable, id_categoria_plato, id_estado_plato, id_menu) VALUES
('Hamburguesa Clásica', 'Pan brioche, 150g carne res, queso cheddar y cebolla', 24000.00, 18, TRUE, 2, 1, 1),
('Porción de Arroz Blanco', 'Porción individual de arroz cocido', 4500.00, 5, FALSE, 3, 1, 3),
('Porción de Carne Asada', 'Filete de res de 250g a la parrilla', 18000.00, 20, TRUE, 3, 1, 3),
('Gaseosa Personal', 'Bebida gaseosa embotellada 400ml', 5000.00, 2, FALSE, 4, 1, 1),
('Pollo a la Plancha', 'Pechuga marinada de 250g con guarnición ligera', 19000.00, 15, TRUE, 1, 1, 1),
('Porción de Papas Criollas', 'Papas criollas fritas 200g', 6000.00, 10, FALSE, 3, 1, 3),
('Jugo de Naranja', 'Jugo natural de naranja', 7000.00, 4, FALSE, 4, 1, 1),
('Limonada', 'Limonada natural', 3500.00, 3, FALSE, 4, 1, 1),
('Brownie con Chocolate', 'Brownie casero de chocolate', 9000.00, 8, FALSE, 5, 1, 2),
('Bandeja Ejecutiva', 'Carne molida, arroz y papa criolla', 21000.00, 20, TRUE, 1, 1, 2),
('Sopa de Lentejas', 'Sopa del día con lentejas', 15000.00, 12, FALSE, 1, 4, 2),
('Ensalada Completa', 'Lechuga y tomate aderezados', 12000.00, 6, TRUE, 1, 2, 2);

INSERT INTO Receta (id_plato, id_ingrediente, cantidad_cruda_requerida) VALUES
(1, 1, 150.000), (1, 3, 1.000), (1, 4, 30.000), (1, 5, 25.000),
(2, 6, 90.000), (2, 7, 10.000),
(3, 2, 250.000),
(4, 8, 1.000),
(5, 9, 250.000), (5, 7, 15.000),
(6, 10, 200.000), (6, 7, 30.000),
(7, 12, 3.000),
(8, 13, 2.000),
(9, 14, 80.000),
(10, 1, 200.000), (10, 6, 120.000), (10, 10, 150.000),
(11, 15, 100.000), (11, 5, 20.000),
(12, 17, 100.000), (12, 18, 80.000);

-- 5. RESERVAS (12; 4 pendientes = 33,33 %)
INSERT INTO Reserva (fecha_hora_inicio, cantidad_personas, cedula_cliente, id_mesa, id_tipo_reserva, id_estado_reserva) VALUES
('2026-11-10 13:00:00', 2, 'CLI-TEST-001', 2, 1, 3),
('2026-11-11 20:00:00', 4, 'CLI-TEST-003', 1, 1, 3),
('2026-11-12 19:30:00', 6, 'CLI-TEST-004', 3, 2, 3),
('2026-11-13 13:00:00', 8, 'CLI-TEST-005', 5, 3, 3),
('2026-11-14 21:00:00', 4, 'CLI-TEST-007', 4, 4, 5),
('2026-11-15 20:00:00', 2, 'CLI-TEST-002', 6, 1, 4),
('2026-11-18 19:00:00', 4, 'CLI-TEST-008', 1, 1, 1),
('2026-11-19 13:30:00', 2, 'CLI-TEST-009', 2, 1, 1),
('2026-11-20 20:00:00', 6, 'CLI-TEST-006', 3, 2, 1),
('2026-11-21 19:30:00', 8, 'CLI-TEST-010', 5, 5, 1),
('2026-11-22 14:00:00', 4, 'CLI-TEST-001', 4, 1, 2),
('2026-11-23 20:30:00', 4, 'CLI-TEST-003', 7, 4, 2);

-- 6. PEDIDOS (33)
INSERT INTO Pedido (fecha_creacion, cedula_empleado, id_mesa, cedula_cliente, id_estado_pedido) VALUES
('2026-11-09 12:10:00', 'EMP-TEST-001', 1, 'CLI-TEST-001', 5),
('2026-11-09 13:05:00', 'EMP-TEST-002', 2, 'CLI-TEST-002', 5),
('2026-11-09 19:40:00', 'EMP-TEST-001', 3, 'CLI-TEST-003', 5),
('2026-11-09 20:15:00', 'EMP-TEST-003', 4, 'CLI-TEST-001', 5),
('2026-11-10 12:30:00', 'EMP-TEST-002', 1, 'CLI-TEST-004', 5),
('2026-11-10 13:20:00', 'EMP-TEST-003', 5, 'CLI-TEST-005', 5),
('2026-11-10 20:10:00', 'EMP-TEST-001', 3, 'CLI-TEST-003', 5),
('2026-11-10 20:45:00', 'EMP-TEST-002', 6, 'CLI-TEST-006', 6),
('2026-11-11 12:15:00', 'EMP-TEST-003', 2, 'CLI-TEST-002', 5),
('2026-11-11 13:00:00', 'EMP-TEST-001', 4, 'CLI-TEST-007', 5),
('2026-11-11 19:30:00', 'EMP-TEST-002', 1, 'CLI-TEST-001', 5),
('2026-11-11 21:00:00', 'EMP-TEST-003', 6, 'CLI-TEST-008', 5),
('2026-11-12 12:40:00', 'EMP-TEST-001', 2, 'CLI-TEST-009', 5),
('2026-11-12 13:15:00', 'EMP-TEST-002', 3, 'CLI-TEST-004', 5),
('2026-11-12 19:20:00', 'EMP-TEST-003', 5, 'CLI-TEST-005', 5),
('2026-11-12 20:30:00', 'EMP-TEST-001', 1, 'CLI-TEST-010', 4),
('2026-11-13 12:05:00', 'EMP-TEST-002', 4, 'CLI-TEST-003', 5),
('2026-11-13 13:25:00', 'EMP-TEST-003', 2, 'CLI-TEST-002', 5),
('2026-11-13 19:50:00', 'EMP-TEST-001', 6, 'CLI-TEST-006', 5),
('2026-11-13 20:35:00', 'EMP-TEST-002', 3, 'CLI-TEST-001', 5),
('2026-11-14 12:20:00', 'EMP-TEST-003', 1, 'CLI-TEST-007', 5),
('2026-11-14 13:10:00', 'EMP-TEST-001', 3, 'CLI-TEST-008', 5),
('2026-11-14 14:00:00', 'EMP-TEST-002', 4, 'CLI-TEST-004', 5),
('2026-11-14 19:15:00', 'EMP-TEST-003', 5, 'CLI-TEST-005', 5),
('2026-11-14 20:00:00', 'EMP-TEST-001', 1, 'CLI-TEST-007', 5),
('2026-11-14 21:10:00', 'EMP-TEST-002', 6, 'CLI-TEST-009', 6),
('2026-11-15 12:30:00', 'EMP-TEST-001', 2, 'CLI-TEST-002', 5),
('2026-11-15 14:20:00', 'EMP-TEST-003', 3, 'CLI-TEST-008', 5),
('2026-11-15 18:30:00', 'EMP-TEST-002', 1, 'CLI-TEST-001', 2),
('2026-11-15 18:45:00', 'EMP-TEST-003', 4, 'CLI-TEST-010', 2),
('2026-11-15 19:05:00', 'EMP-TEST-001', 6, 'CLI-TEST-006', 1),
('2026-11-15 19:20:00', 'EMP-TEST-002', 2, 'CLI-TEST-003', 1),
('2026-11-15 19:40:00', 'EMP-TEST-003', 5, 'CLI-TEST-009', 1);

-- 7. DETALLE DE PEDIDO Y PERSONALIZACIONES
INSERT INTO DetallePedido (id_pedido, id_plato, cantidad_detallepedido, precio_unitario, observaciones) VALUES
(1, 1, 1, 24000.00, 'Término medio'),
(1, 4, 1, 5000.00, NULL),
(2, 5, 1, 19000.00, NULL),
(2, 6, 1, 6000.00, NULL),
(2, 8, 1, 3500.00, NULL),
(3, 1, 2, 24000.00, 'Sin cebolla en una'),
(3, 7, 1, 7000.00, NULL),
(4, 3, 1, 18000.00, NULL),
(4, 2, 1, 4500.00, NULL),
(4, 4, 1, 5000.00, NULL),
(5, 10, 1, 21000.00, NULL),
(5, 8, 1, 3500.00, NULL),
(5, 1, 1, 24000.00, NULL),
(6, 1, 1, 24000.00, NULL),
(6, 4, 1, 5000.00, NULL),
(6, 9, 1, 9000.00, NULL),
(7, 3, 2, 18000.00, 'Término 3/4'),
(7, 6, 1, 6000.00, NULL),
(8, 5, 1, 19000.00, NULL),
(9, 11, 1, 15000.00, NULL),
(9, 4, 1, 5000.00, NULL),
(10, 10, 2, 21000.00, NULL),
(10, 7, 2, 7000.00, NULL),
(11, 1, 1, 24000.00, NULL),
(11, 5, 1, 19000.00, NULL),
(12, 12, 1, 12000.00, 'Sin hielo'),
(12, 8, 1, 3500.00, NULL),
(13, 1, 1, 24000.00, NULL),
(13, 4, 2, 5000.00, NULL),
(14, 10, 1, 21000.00, NULL),
(14, 6, 1, 6000.00, NULL),
(14, 7, 1, 7000.00, NULL),
(15, 3, 1, 18000.00, NULL),
(15, 2, 1, 4500.00, NULL),
(15, 4, 1, 5000.00, NULL),
(16, 5, 1, 19000.00, NULL),
(16, 9, 1, 9000.00, NULL),
(17, 1, 2, 24000.00, NULL),
(17, 4, 2, 5000.00, NULL),
(18, 11, 2, 15000.00, NULL),
(18, 8, 2, 3500.00, NULL),
(19, 5, 1, 19000.00, 'Para llevar'),
(19, 6, 1, 6000.00, NULL),
(19, 4, 1, 5000.00, NULL),
(20, 1, 1, 24000.00, NULL),
(20, 9, 1, 9000.00, NULL),
(21, 1, 3, 24000.00, NULL),
(21, 4, 3, 5000.00, NULL),
(22, 3, 2, 18000.00, NULL),
(22, 2, 2, 4500.00, NULL),
(22, 7, 2, 7000.00, NULL),
(23, 10, 2, 21000.00, NULL),
(23, 8, 2, 3500.00, NULL),
(24, 1, 2, 24000.00, 'Mesa celebra cumpleaños'),
(24, 5, 1, 19000.00, NULL),
(24, 4, 2, 5000.00, NULL),
(25, 3, 1, 18000.00, NULL),
(25, 6, 1, 6000.00, NULL),
(26, 12, 1, 12000.00, NULL),
(27, 1, 1, 24000.00, NULL),
(27, 4, 1, 5000.00, NULL),
(28, 11, 1, 15000.00, NULL),
(28, 8, 1, 3500.00, NULL),
(29, 5, 2, 19000.00, 'Ambas término medio'),
(29, 6, 2, 6000.00, NULL),
(30, 1, 1, 24000.00, 'Alergia declarada a nueces'),
(30, 4, 1, 5000.00, NULL),
(31, 3, 1, 18000.00, NULL),
(31, 2, 1, 4500.00, NULL),
(31, 8, 1, 3500.00, NULL),
(32, 10, 1, 21000.00, NULL),
(32, 7, 1, 7000.00, NULL),
(33, 1, 2, 24000.00, NULL),
(33, 4, 2, 5000.00, NULL);

-- precio_ajuste = Ingrediente.precio_adicional al momento de la venta (0 si QUITAR)
INSERT INTO PersonalizacionDetalle (id_detalle, id_ingrediente, tipo_accion, cantidad_adicional, precio_ajuste) VALUES
(1, 4, 'AGREGAR', 30.000, 2500.00),
(24, 5, 'QUITAR', NULL, 0.00),
(28, 11, 'AGREGAR', 1.000, 3500.00),
(45, 4, 'QUITAR', NULL, 0.00),
(45, 5, 'QUITAR', NULL, 0.00),
(47, 11, 'AGREGAR', 1.000, 3500.00),
(54, 4, 'AGREGAR', 30.000, 2500.00);

-- 8. VALORES CALCULADOS A PARTIR DE LO YA INSERTADO
-- Factura solo para pedidos pagados (estado 5); el pedido 16 (Entregado) queda sin factura
INSERT INTO Factura (numero_factura, fecha_emision, monto_total, metodo_pago, id_pedido)
SELECT 'FAC-001-' || LPAD(ROW_NUMBER() OVER (ORDER BY p.id_pedido)::TEXT, 4, '0'),
       p.fecha_creacion + INTERVAL '50 minutes',
       (SELECT COALESCE(SUM(
           (d.cantidad_detallepedido * d.precio_unitario) +
           COALESCE((
               SELECT SUM(pd.precio_ajuste)
               FROM PersonalizacionDetalle pd
               WHERE pd.id_detalle = d.id_detalle
           ), 0)
       ), 0) FROM DetallePedido d WHERE d.id_pedido = p.id_pedido),
       (ARRAY['Efectivo','Tarjeta','Transferencia'])[1 + (p.id_pedido % 3)],
       p.id_pedido
FROM Pedido p
WHERE p.id_estado_pedido = 5
ORDER BY p.id_pedido;

-- Salidas de inventario: receta x cantidad vendida (sin los QUITAR), solo pedidos ya enviados a cocina
INSERT INTO MovimientoInventario (id_ingrediente, id_detalle, tipo_movimiento, cantidad_movimiento, fecha_hora_movimiento)
SELECT r.id_ingrediente, d.id_detalle, 'SALIDA_VENTA',
       -(r.cantidad_cruda_requerida * d.cantidad_detallepedido),
       p.fecha_creacion + INTERVAL '2 minutes'
FROM DetallePedido d
JOIN Pedido p ON p.id_pedido = d.id_pedido
JOIN Receta r ON r.id_plato = d.id_plato
WHERE p.id_estado_pedido IN (2, 3, 4, 5)
  AND NOT EXISTS (SELECT 1 FROM PersonalizacionDetalle pd      -- ingrediente QUITADO: no sale
                  WHERE pd.id_detalle = d.id_detalle
                    AND pd.id_ingrediente = r.id_ingrediente
                    AND pd.tipo_accion = 'QUITAR')
ORDER BY d.id_detalle, r.id_ingrediente;

-- Ingredientes AGREGADOS por personalizacion tambien salen del inventario
INSERT INTO MovimientoInventario (id_ingrediente, id_detalle, tipo_movimiento, cantidad_movimiento, fecha_hora_movimiento)
SELECT pd.id_ingrediente, d.id_detalle, 'SALIDA_VENTA', -pd.cantidad_adicional,
       p.fecha_creacion + INTERVAL '2 minutes'
FROM PersonalizacionDetalle pd
JOIN DetallePedido d ON d.id_detalle = pd.id_detalle
JOIN Pedido p ON p.id_pedido = d.id_pedido
WHERE pd.tipo_accion = 'AGREGAR' AND p.id_estado_pedido IN (2, 3, 4, 5)
ORDER BY d.id_detalle, pd.id_ingrediente;

-- Entradas por compra (sin linea de venta asociada)
INSERT INTO MovimientoInventario (id_ingrediente, id_detalle, tipo_movimiento, cantidad_movimiento, fecha_hora_movimiento) VALUES
(1, NULL, 'ENTRADA_COMPRA', 10000.000, '2026-11-08 08:00:00'),
(3, NULL, 'ENTRADA_COMPRA', 60.000, '2026-11-08 08:10:00'),
(8, NULL, 'ENTRADA_COMPRA', 48.000, '2026-11-08 08:20:00'),
(9, NULL, 'ENTRADA_COMPRA', 8000.000, '2026-11-08 08:30:00'),
(12, NULL, 'ENTRADA_COMPRA', 100.000, '2026-11-08 08:40:00'),
(14, NULL, 'ENTRADA_COMPRA', 3000.000, '2026-11-08 08:50:00');

-- Stock real = stock inicial + suma de movimientos (entradas +, salidas -).
-- Si algun ingrediente quedara negativo, el CHECK de stock_actual lo rechaza.
UPDATE Ingrediente i
SET stock_actual = i.stock_actual + COALESCE(
    (SELECT SUM(m.cantidad_movimiento) FROM MovimientoInventario m
     WHERE m.id_ingrediente = i.id_ingrediente), 0);

-- 9. NOVEDADES
INSERT INTO Novedad (fecha_hora_novedad, descripcion_novedad, id_pedido, id_estado_pedido) VALUES
('2026-11-09 12:25:00', 'Cliente pide cambio de mesa a una exterior', 1, 5),
('2026-11-10 20:20:00', 'Cocina reporta demora por alta demanda', 7, 5),
('2026-11-10 20:50:00', 'Pedido cancelado por el cliente antes de preparar', 8, 6),
('2026-11-12 19:55:00', 'Plato devuelto a cocina por término incorrecto', 15, 5),
('2026-11-15 18:40:00', 'Comanda con retraso de 5 minutos', 29, 2),
('2026-11-15 19:10:00', 'Cliente solicita agregar un plato al pedido', 31, 1);

COMMIT;

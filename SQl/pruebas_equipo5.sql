-- =============================================================
-- PRUEBAS - SISTEMA DE GESTION DE RESTAURANTE (PostgreSQL)
-- Equipo 5 - Bases de Datos
-- Archivo 5 de 6. AQUI LOS ERRORES SON EL RESULTADO ESPERADO.
-- Correr con psql (sigue despues de un error). Requiere haber corrido
-- esquema_equipo5.sql, poblar_equipo5.sql y vistas_permisos_equipo5.sql.
--
-- Reglas de este archivo:
--   * Cada rechazo va FUERA de BEGIN: en PostgreSQL una sentencia que falla
--     deja inservible la transaccion hasta el ROLLBACK.
--   * Los INSERT usan id explicito alto (9001...) para que (a) no choquen
--     con la llave que no se esta probando y (b) no avancen los SERIAL.
--   * Al terminar, la base queda como la dejo poblar_ (la huella del
--     final se compara con la del inicio).
-- =============================================================

-- Huella de la base ANTES de las pruebas (tablas temporales: no quedan en la base)
CREATE TEMP TABLE _huella_antes AS
SELECT t.table_name,
       md5(query_to_xml(format('SELECT * FROM %I ORDER BY 1', t.table_name), false, true, '')::text) AS huella
FROM information_schema.tables t
WHERE t.table_schema = 'public' AND t.table_type = 'BASE TABLE';

CREATE TEMP TABLE _secuencias_antes AS
SELECT sequencename, last_value FROM pg_sequences WHERE schemaname = 'public';

-- =============================================================
-- PARTE 1. UN RECHAZO POR TIPO DE RESTRICCION
-- =============================================================

SELECT 'P1 PRIMARY KEY' AS prueba;
-- Regla: cada mesa fisica tiene un identificador que no se repite.
-- Rechaza: mesa_pkey (id_mesa = 1 ya existe; numero_mesa 99 es nuevo, asi que
-- la unica restriccion que falla es la PK).
INSERT INTO Mesa (id_mesa, numero_mesa, capacidad_mesa, id_estado_mesa)
VALUES (1, 99, 4, 1);

SELECT 'P2 UNIQUE (llave alterna)' AS prueba;
-- Regla: no pueden existir dos mesas con el mismo numero impreso.
-- Rechaza: mesa_numero_mesa_key (numero_mesa = 1 ya existe; id 9001 es nuevo).
INSERT INTO Mesa (id_mesa, numero_mesa, capacidad_mesa, id_estado_mesa)
VALUES (9001, 1, 4, 1);

SELECT 'P2b UNIQUE (llave alterna: nombre del plato)' AS prueba;
-- Regla: no hay dos platos con el mismo nombre en la carta.
-- Rechaza: plato_nombre_plato_key ('Hamburguesa Clásica' ya existe; id 9001 es
-- nuevo y categoria, estado y menu existen).
INSERT INTO Plato (id_plato, nombre_plato, precio_base, id_categoria_plato, id_estado_plato, id_menu)
VALUES (9001, 'Hamburguesa Clásica', 1000.00, 2, 1, 1);

SELECT 'P2c UNIQUE (llave alterna: nombre del menu)' AS prueba;
-- Regla: no hay dos menus con el mismo nombre.
-- Rechaza: menu_nombre_menu_key ('Menú Principal 2026' ya existe; id 9001 es nuevo).
INSERT INTO Menu (id_menu, nombre_menu, id_estado_menu)
VALUES (9001, 'Menú Principal 2026', 1);

SELECT 'P3 UNIQUE (compuesta)' AS prueba;
-- Regla: un ingrediente aparece una sola vez en la receta de un plato.
-- Rechaza: uq_receta_plato_ingrediente (el plato 1 ya usa el ingrediente 1).
INSERT INTO Receta (id_receta, id_plato, id_ingrediente, cantidad_cruda_requerida)
VALUES (9001, 1, 1, 100.000);

SELECT 'P4 NOT NULL' AS prueba;
-- Regla: el sistema es solo dine-in; todo pedido tiene mesa.
-- Rechaza: NOT NULL de pedido.id_mesa (id 9001 nuevo, empleado, cliente y
-- estado validos: ninguna otra restriccion falla antes).
INSERT INTO Pedido (id_pedido, cedula_empleado, id_mesa, cedula_cliente, id_estado_pedido)
VALUES (9001, 'EMP-TEST-001', NULL, 'CLI-TEST-001', 1);

SELECT 'P5 FOREIGN KEY' AS prueba;
-- Regla: no existe reserva sin un cliente registrado que la solicite.
-- Rechaza: reserva_cedula_cliente_fkey (mesa 1, tipo 1 y estado 1 existen).
INSERT INTO Reserva (id_reserva, fecha_hora_inicio, cantidad_personas, cedula_cliente, id_mesa, id_tipo_reserva, id_estado_reserva)
VALUES (9001, '2026-12-01 20:00:00', 2, 'CLI-TEST-999', 1, 1, 1);

SELECT 'P6 CHECK de negocio: unidad de medida' AS prueba;
-- Regla: la unidad de medida de un ingrediente es de dominio cerrado (g, ml, unidad).
-- Rechaza: chk_ingrediente_unidad ('kilos' no esta en el dominio; el resto de
-- columnas es valido).
INSERT INTO Ingrediente (id_ingrediente, nombre_ingrediente, unidad_medida, stock_actual, stock_minimo)
VALUES (9001, 'Ingrediente Prueba', 'kilos', 10.000, 1.000);

SELECT 'P6b CHECK de columna: el stock nunca queda negativo' AS prueba;
-- Regla: una salida no puede dejar el inventario de un ingrediente por debajo de cero
-- (es la razon de conservar Ingrediente.stock_actual; ver A.4 del informe).
-- Rechaza: el CHECK (stock_actual >= 0) de la columna (se intenta descontar 1.000.000 g
-- a la carne molida, que tiene unos 21.000 g; la fila no cambia).
UPDATE Ingrediente SET stock_actual = stock_actual - 1000000.000 WHERE id_ingrediente = 1;

SELECT 'P7 CHECK de negocio: signo del movimiento' AS prueba;
-- Regla: una venta nunca suma stock (las salidas son negativas).
-- Rechaza: chk_movimiento_signo (SALIDA_VENTA con cantidad positiva).
INSERT INTO MovimientoInventario (id_movimiento, id_ingrediente, id_detalle, tipo_movimiento, cantidad_movimiento)
VALUES (9001, 1, NULL, 'SALIDA_VENTA', 10.000);

SELECT 'P8 CHECK de negocio: personalizacion' AS prueba;
-- Regla: agregar un ingrediente a un plato exige una cantidad mayor que cero.
-- Rechaza: chk_personalizacion_reglas (AGREGAR con cantidad 0; 'AGREGAR' si
-- esta en el dominio de tipo_accion, por eso no cae en el CHECK de la columna).
INSERT INTO PersonalizacionDetalle (id_personalizacion, id_detalle, id_ingrediente, tipo_accion, cantidad_adicional)
VALUES (9001, 1, 4, 'AGREGAR', 0.000);

SELECT 'P8b CHECK de columna: precio_ajuste no negativo' AS prueba;
-- Regla: el recargo de una personalizacion nunca es negativo.
-- Rechaza: el CHECK (precio_ajuste >= 0) de la columna (QUITAR con cantidad NULL
-- cumple chk_personalizacion_reglas, asi que la unica restriccion que falla es esta).
INSERT INTO PersonalizacionDetalle (id_personalizacion, id_detalle, id_ingrediente, tipo_accion, cantidad_adicional, precio_ajuste)
VALUES (9002, 1, 5, 'QUITAR', NULL, -500.00);

-- =============================================================
-- PARTE 2. ON DELETE: DELETE DE UN PADRE RECHAZADO Y BORRADO EN ORDEN
-- =============================================================

SELECT 'P9 DELETE rechazado: catalogo (RESTRICT)' AS prueba;
-- Regla: un estado de menu en uso no se borra ("nada se borra").
-- Rechaza: menu_id_estado_menu_fkey (solo Menu referencia a EstadoMenu).
DELETE FROM EstadoMenu WHERE id_estado_menu = 1;

SELECT 'P10 DELETE rechazado: pedido con factura (RESTRICT)' AS prueba;
-- Regla: las ventas son intocables; un pedido facturado no se borra.
-- Rechaza: factura_id_pedido_fkey (Detalle y Novedad son CASCADE y no bloquean).
DELETE FROM Pedido WHERE id_pedido = 1;

SELECT 'P11 DELETE en el orden correcto, dentro de una transaccion que se deshace' AS prueba;
-- Columnas: pedidos | facturas | detalles | personalizaciones | novedades | movimientos sin detalle
-- (todo del pedido 1, salvo pedidos, que es el total de la tabla).
SELECT (SELECT COUNT(*) FROM Pedido)                                          AS pedidos,
       (SELECT COUNT(*) FROM Factura WHERE id_pedido = 1)                     AS facturas_p1,
       (SELECT COUNT(*) FROM DetallePedido WHERE id_pedido = 1)               AS detalles_p1,
       (SELECT COUNT(*) FROM PersonalizacionDetalle pd
          JOIN DetallePedido d ON d.id_detalle = pd.id_detalle
         WHERE d.id_pedido = 1)                                               AS personalizaciones_p1,
       (SELECT COUNT(*) FROM Novedad WHERE id_pedido = 1)                     AS novedades_p1,
       (SELECT COUNT(*) FROM MovimientoInventario WHERE id_detalle IS NULL)   AS movimientos_sin_detalle,
       'ANTES' AS momento;
BEGIN;
DELETE FROM Factura WHERE id_pedido = 1;   -- 1o: la factura (RESTRICT) que bloqueaba
DELETE FROM Pedido  WHERE id_pedido = 1;   -- 2o: el pedido; arrastra detalle, personalizacion y novedad (CASCADE)
SELECT (SELECT COUNT(*) FROM Pedido)                                          AS pedidos,
       (SELECT COUNT(*) FROM Factura WHERE id_pedido = 1)                     AS facturas_p1,
       (SELECT COUNT(*) FROM DetallePedido WHERE id_pedido = 1)               AS detalles_p1,
       (SELECT COUNT(*) FROM PersonalizacionDetalle pd
          JOIN DetallePedido d ON d.id_detalle = pd.id_detalle
         WHERE d.id_pedido = 1)                                               AS personalizaciones_p1,
       (SELECT COUNT(*) FROM Novedad WHERE id_pedido = 1)                     AS novedades_p1,
       (SELECT COUNT(*) FROM MovimientoInventario WHERE id_detalle IS NULL)   AS movimientos_sin_detalle,
       'DURANTE' AS momento;
ROLLBACK;
SELECT (SELECT COUNT(*) FROM Pedido)                                          AS pedidos,
       (SELECT COUNT(*) FROM Factura WHERE id_pedido = 1)                     AS facturas_p1,
       (SELECT COUNT(*) FROM DetallePedido WHERE id_pedido = 1)               AS detalles_p1,
       (SELECT COUNT(*) FROM PersonalizacionDetalle pd
          JOIN DetallePedido d ON d.id_detalle = pd.id_detalle
         WHERE d.id_pedido = 1)                                               AS personalizaciones_p1,
       (SELECT COUNT(*) FROM Novedad WHERE id_pedido = 1)                     AS novedades_p1,
       (SELECT COUNT(*) FROM MovimientoInventario WHERE id_detalle IS NULL)   AS movimientos_sin_detalle,
       'DESPUES' AS momento;
-- Lectura: durante la transaccion el pedido, su factura, sus detalles, su
-- personalizacion y su novedad desaparecen (CASCADE), y los movimientos de
-- inventario de esos detalles se CONSERVAN con id_detalle = NULL (SET NULL).
-- Despues del ROLLBACK todo vuelve a los valores de ANTES.

SELECT 'P12 DELETE rechazado: ingrediente usado en una receta (RESTRICT)' AS prueba;
-- Se crea un ingrediente de prueba solo usado por una receta (para que la
-- unica FK que lo proteja sea la de Receta), se intenta borrar y luego se
-- borra en el orden correcto: primero la receta, despues el ingrediente.
INSERT INTO Ingrediente (id_ingrediente, nombre_ingrediente, unidad_medida, stock_actual, stock_minimo)
VALUES (9001, 'Ingrediente Prueba', 'g', 10.000, 1.000);
INSERT INTO Receta (id_receta, id_plato, id_ingrediente, cantidad_cruda_requerida)
VALUES (9001, 12, 9001, 5.000);
-- Rechaza: receta_id_ingrediente_fkey (la receta no puede quedar rota).
DELETE FROM Ingrediente WHERE id_ingrediente = 9001;
-- Orden correcto: primero las recetas que lo usan, despues el ingrediente.
BEGIN;
DELETE FROM Receta WHERE id_ingrediente = 9001;
DELETE FROM Ingrediente WHERE id_ingrediente = 9001;
COMMIT;

-- =============================================================
-- PARTE 3. UPDATE CON SU CONTEO PREVIO
-- =============================================================

SELECT 'P13 UPDATE con conteo previo' AS prueba;
-- Cambio: las bebidas disponibles suben 10 %.
-- 1) Conteo previo con el MISMO WHERE que usara el UPDATE.
SELECT COUNT(*) AS filas_que_cumplen
FROM Plato
WHERE id_categoria_plato = 4 AND id_estado_plato = 1;      -- esperado: 3
-- Ventas pagadas calculadas desde sus lineas (vista temporal: no queda en la base).
CREATE TEMP VIEW _ventas_pagadas AS
SELECT COALESCE(SUM(d.cantidad_detallepedido * d.precio_unitario
         + COALESCE((SELECT SUM(pd.precio_ajuste) FROM PersonalizacionDetalle pd
                     WHERE pd.id_detalle = d.id_detalle), 0)), 0) AS ventas_pagadas
FROM DetallePedido d JOIN Pedido p ON p.id_pedido = d.id_pedido
WHERE p.id_estado_pedido = 5;
SELECT ventas_pagadas, 'ANTES' AS momento FROM _ventas_pagadas;
BEGIN;
UPDATE Plato
SET precio_base = ROUND(precio_base * 1.10, 2)
WHERE id_categoria_plato = 4 AND id_estado_plato = 1
RETURNING nombre_plato, precio_base;                        -- esperado: UPDATE 3
-- Tambien sube el recargo de un ingrediente adicional (precio actual del catalogo).
UPDATE Ingrediente SET precio_adicional = precio_adicional * 2 WHERE precio_adicional > 0;
-- Los dos numeros coinciden (3 y 3). Las ventas ya registradas no cambian:
-- DetallePedido.precio_unitario y PersonalizacionDetalle.precio_ajuste guardan
-- lo cobrado en su momento; ventas_pagadas DURANTE debe ser igual a ANTES.
SELECT ventas_pagadas, 'DURANTE' AS momento FROM _ventas_pagadas;
ROLLBACK;
SELECT ventas_pagadas, 'DESPUES' AS momento FROM _ventas_pagadas;
SELECT nombre_plato, precio_base FROM Plato WHERE id_categoria_plato = 4 ORDER BY id_plato;   -- precios originales

-- =============================================================
-- PARTE 4. BEGIN ... ROLLBACK CON CONTEO ANTES, DURANTE Y DESPUES
-- =============================================================

SELECT 'P14 BEGIN ... ROLLBACK' AS prueba;
SELECT (SELECT COUNT(*) FROM Pedido) AS pedidos, (SELECT COUNT(*) FROM DetallePedido) AS detalles, 'ANTES' AS momento;
BEGIN;
INSERT INTO Pedido (id_pedido, fecha_creacion, cedula_empleado, id_mesa, cedula_cliente, id_estado_pedido)
VALUES (9001, '2026-11-16 12:00:00', 'EMP-TEST-001', 7, 'CLI-TEST-002', 1);
INSERT INTO DetallePedido (id_detalle, id_pedido, id_plato, cantidad_detallepedido, precio_unitario)
VALUES (9001, 9001, 1, 1, 24000.00);
SELECT (SELECT COUNT(*) FROM Pedido) AS pedidos, (SELECT COUNT(*) FROM DetallePedido) AS detalles, 'DURANTE' AS momento;
ROLLBACK;
SELECT (SELECT COUNT(*) FROM Pedido) AS pedidos, (SELECT COUNT(*) FROM DetallePedido) AS detalles, 'DESPUES' AS momento;

-- =============================================================
-- PARTE 5. UNA REGLA QUE EL ESQUEMA NO VIGILA (la resuelve la aplicacion)
-- =============================================================

SELECT 'P15 regla NO vigilada: reservas solapadas en la misma mesa' AS prueba;
-- Regla: dos reservas de una misma mesa no pueden cruzarse en el tiempo.
-- Ninguna restriccion la cubre: la duracion vive en TipoReserva y un CHECK o
-- UNIQUE no puede cruzar tablas. El INSERT siguiente NO es rechazado; la
-- consulta cuenta los pares de reservas que se cruzan (misma mesa, no canceladas).
SELECT COUNT(*) AS pares_solapados, 'ANTES' AS momento
FROM Reserva r1
JOIN TipoReserva t1 ON t1.id_tipo_reserva = r1.id_tipo_reserva
JOIN Reserva r2 ON r2.id_mesa = r1.id_mesa AND r2.id_reserva > r1.id_reserva
JOIN TipoReserva t2 ON t2.id_tipo_reserva = r2.id_tipo_reserva
WHERE r1.id_estado_reserva <> 4 AND r2.id_estado_reserva <> 4
  AND r1.fecha_hora_inicio < r2.fecha_hora_inicio + t2.duracion_horas * INTERVAL '1 hour'
  AND r2.fecha_hora_inicio < r1.fecha_hora_inicio + t1.duracion_horas * INTERVAL '1 hour';
BEGIN;
-- La reserva 2 es de la mesa 1 el 11-nov a las 20:00 (tipo Estandar, 2 h): esta
-- reserva empieza a las 21:00, o sea durante la anterior. Ademas el comentario
-- de capacidad: la mesa 1 es de 4 personas y aqui se piden 20; tampoco se rechaza.
INSERT INTO Reserva (id_reserva, fecha_hora_inicio, cantidad_personas, cedula_cliente, id_mesa, id_tipo_reserva, id_estado_reserva)
VALUES (9001, '2026-11-11 21:00:00', 20, 'CLI-TEST-002', 1, 1, 1);          -- esperado: INSERT 0 1
SELECT COUNT(*) AS pares_solapados, 'DURANTE' AS momento
FROM Reserva r1
JOIN TipoReserva t1 ON t1.id_tipo_reserva = r1.id_tipo_reserva
JOIN Reserva r2 ON r2.id_mesa = r1.id_mesa AND r2.id_reserva > r1.id_reserva
JOIN TipoReserva t2 ON t2.id_tipo_reserva = r2.id_tipo_reserva
WHERE r1.id_estado_reserva <> 4 AND r2.id_estado_reserva <> 4
  AND r1.fecha_hora_inicio < r2.fecha_hora_inicio + t2.duracion_horas * INTERVAL '1 hour'
  AND r2.fecha_hora_inicio < r1.fecha_hora_inicio + t1.duracion_horas * INTERVAL '1 hour';
ROLLBACK;
-- Lectura: el motor acepta una reserva que se cruza con otra y que excede la
-- capacidad de la mesa. Verificarlo antes de insertar es trabajo de la aplicacion.

-- =============================================================
-- PARTE 6. PERMISOS: ROLES, VISTAS Y REVOKE
-- =============================================================

SELECT 'P16 rol_consulta lee las vistas (debe funcionar)' AS prueba;
-- Regla: quien consulta ve el estado y el total de los pedidos y la lista de
-- clientes, sin necesitar permiso sobre ninguna tabla.
-- Acepta: la vista se ejecuta con los privilegios de su dueño, no del rol.
SET ROLE rol_consulta;
SELECT COUNT(*) AS pedidos_en_vista  FROM v_pedido_publico;      -- esperado: igual al total de Pedido
SELECT COUNT(*) AS clientes_en_vista FROM v_cliente_publico;     -- esperado: igual al total de Cliente
RESET ROLE;
-- Lectura: el rol de consulta obtiene datos reales a través de las dos vistas.

SELECT 'P17 rol_consulta rechazado en las tablas' AS prueba;
-- Regla: quien consulta no accede a las tablas base ni a los datos de contacto del cliente.
-- Rechaza: falta de GRANT SELECT sobre Pedido y Cliente (permission denied for table).
-- La tercera sentencia falla distinto: la vista no tiene la columna.
SET ROLE rol_consulta;
SELECT COUNT(*) FROM Pedido;                 -- esperado: permission denied for table pedido
SELECT telefono FROM Cliente;                -- esperado: permission denied for table cliente
SELECT telefono FROM v_cliente_publico;      -- esperado: column "telefono" does not exist
RESET ROLE;
-- Lectura: la misma consulta que funciona en la vista es rechazada en la tabla,
-- y el teléfono no se puede pedir ni por la vista porque ésta no lo expone.

SELECT 'P18 rol_operacion rechazado al borrar ventas' AS prueba;
-- Regla: quien atiende pedidos los crea y modifica, pero las ventas son
-- intocables ("nada se borra").
-- Rechaza: rol_operacion no tiene DELETE sobre Pedido ni ningún permiso sobre Factura.
SET ROLE rol_operacion;
SELECT COUNT(*) FROM Pedido;                 -- esperado: funciona (tiene SELECT)
DELETE FROM Pedido WHERE id_pedido = 1;      -- esperado: permission denied for table pedido
DELETE FROM Factura WHERE id_pedido = 1;     -- esperado: permission denied for table factura
RESET ROLE;
-- Lectura: puede leer pedidos, pero no borrarlos ni tocar la facturación.

SELECT 'P19 REVOKE y su rechazo' AS prueba;
-- Regla: un permiso concedido se puede retirar y el rechazo es inmediato.
-- Rechaza: tras el REVOKE, rol_consulta pierde SELECT sobre v_pedido_publico.
REVOKE SELECT ON v_pedido_publico FROM rol_consulta;
SET ROLE rol_consulta;
SELECT COUNT(*) FROM v_pedido_publico;       -- esperado: permission denied for view v_pedido_publico
RESET ROLE;
GRANT SELECT ON v_pedido_publico TO rol_consulta;   -- se deja todo como estaba
-- Lectura: la misma consulta que funcionaba en P16 ahora es rechazada; el
-- GRANT final restaura el permiso para que la base quede como estaba.

-- =============================================================
-- CIERRE: LA BASE QUEDO COMO LA DEJO poblar_
-- =============================================================

SELECT 'CIERRE: tablas cuyo contenido cambio (debe ser 0)' AS prueba;
SELECT COUNT(*) AS tablas_distintas
FROM _huella_antes a
JOIN (SELECT t.table_name,
             md5(query_to_xml(format('SELECT * FROM %I ORDER BY 1', t.table_name), false, true, '')::text) AS huella
      FROM information_schema.tables t
      WHERE t.table_schema = 'public' AND t.table_type = 'BASE TABLE') d
  ON d.table_name = a.table_name
WHERE d.huella <> a.huella;

SELECT 'CIERRE: secuencias que avanzaron (debe ser 0)' AS prueba;
SELECT COUNT(*) AS secuencias_distintas
FROM _secuencias_antes s
JOIN pg_sequences q ON q.schemaname = 'public' AND q.sequencename = s.sequencename
WHERE q.last_value IS DISTINCT FROM s.last_value;

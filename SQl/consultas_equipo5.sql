-- =============================================================
-- CONSULTAS - SISTEMA DE GESTION DE RESTAURANTE (PostgreSQL)
-- Equipo 5 - Bases de Datos
-- Archivo 4 de 6. Las diez preguntas del negocio. Corre sin errores sobre
-- esquema_equipo5.sql + poblar_equipo5.sql.
-- Cada consulta lleva: la pregunta, el resultado que dio y tres frases
-- (que veo / que significa / que decido).
-- AVISO: son datos de prueba (9 al 15 de nov 2026). Lo que se evalua es que
-- la consulta sirva para decidir, no el hallazgo.
-- Codigos de estado usados: pedido 1 Pendiente, 2 En preparacion, 5 Pagado;
-- reserva 1 Pendiente; categoria 4 Bebidas.
-- =============================================================


-- -------------------------------------------------------------
-- Q1 · WHERE con AND y OR (los parentesis deciden el resultado)
-- PREGUNTA: ¿Que mesas de 4 o mas puestos estan ocupadas o reservadas?
-- RESULTADO: 4 filas: mesas 1, 4 y 5 (ocupadas) y 3 (reservada).
-- QUE VEO: ninguna mesa de 4 o mas puestos esta disponible: las otras dos de
--   ese tamaño son la 7 (en limpieza) y la 8 (fuera de servicio).
-- QUE SIGNIFICA: un grupo de 4 o mas personas que llegue ahora no tiene mesa.
-- QUE DECIDO: avisar la espera a los grupos grandes, limpiar primero la mesa 7
--   y definir cuando se vuelve a poner en servicio la mesa 8.
-- -------------------------------------------------------------
SELECT m.numero_mesa, m.capacidad_mesa, e.nombre_estado_mesa
FROM Mesa m
JOIN EstadoMesa e ON e.id_estado_mesa = m.id_estado_mesa
WHERE (e.nombre_estado_mesa = 'Ocupada' OR e.nombre_estado_mesa = 'Reservada')
  AND m.capacidad_mesa >= 4
ORDER BY m.numero_mesa;

-- Q1-contraste (a proposito SIN parentesis): AND se evalua antes que OR, asi que
-- la condicion de capacidad solo afecta a 'Reservada' y se cuelan las mesas 2 y 6
-- (de 2 puestos). Da 6 filas en vez de 4.
SELECT m.numero_mesa, m.capacidad_mesa, e.nombre_estado_mesa
FROM Mesa m
JOIN EstadoMesa e ON e.id_estado_mesa = m.id_estado_mesa
WHERE e.nombre_estado_mesa = 'Ocupada' OR e.nombre_estado_mesa = 'Reservada'
  AND m.capacidad_mesa >= 4
ORDER BY m.numero_mesa;


-- -------------------------------------------------------------
-- Q2 · ORDER BY + LIMIT con desempate explicito
-- PREGUNTA: ¿Cuales son los 3 platos mas vendidos (pedidos pagados)?
-- RESULTADO: Hamburguesa Clasica 16 unidades ($396.000), Gaseosa Personal
--   16 unidades ($80.000), Limonada 8 unidades ($28.000).
-- QUE VEO: la hamburguesa y la gaseosa empatan en 16 unidades; el desempate
--   por ingresos pone primero a la hamburguesa.
-- QUE SIGNIFICA: la gaseosa se vende tanto como el plato fuerte, pero deja
--   cerca de una quinta parte de los ingresos.
-- QUE DECIDO: asegurar primero el abastecimiento de los ingredientes de la
--   hamburguesa (carne, pan, queso y cebolla) antes que los de cualquier otro plato.
-- Desempate: unidades DESC, luego ingresos DESC, luego nombre ASC (sin el
-- desempate, con LIMIT 1 el orden entre los empatados seria arbitrario).
-- -------------------------------------------------------------
SELECT p.nombre_plato,
       SUM(d.cantidad_detallepedido) AS unidades,
       SUM(
           (d.cantidad_detallepedido * d.precio_unitario) +
           COALESCE((
               SELECT SUM(pd.precio_ajuste)
               FROM PersonalizacionDetalle pd
               WHERE pd.id_detalle = d.id_detalle
           ), 0)
       ) AS ingresos
FROM DetallePedido d
JOIN Pedido pe ON pe.id_pedido = d.id_pedido
JOIN Plato  p  ON p.id_plato   = d.id_plato
WHERE pe.id_estado_pedido = 5                                   -- Pagado
GROUP BY p.id_plato, p.nombre_plato
ORDER BY unidades DESC, ingresos DESC, p.nombre_plato ASC
LIMIT 3;


-- -------------------------------------------------------------
-- Q3 · GROUP BY con COUNT(*) y COUNT(DISTINCT ...)
-- PREGUNTA: Por empleado, ¿cuantos pedidos atendio y a cuantos clientes distintos?
-- RESULTADO: Empleado Prueba 1: 11 pedidos y 8 clientes; Empleado Prueba 2:
--   11 y 6; Empleado Prueba 3: 11 y 7.
-- QUE VEO: los tres atendieron 11 pedidos, pero a 8, 6 y 7 clientes distintos.
-- QUE SIGNIFICA: COUNT(*) cuenta filas (pedidos); COUNT(DISTINCT cedula_cliente)
--   cuenta personas distintas. La diferencia son los pedidos de clientes que
--   repiten con el mismo empleado: 3, 5 y 4 respectivamente.
-- QUE DECIDO: asignar las reservas de clientes frecuentes al Empleado Prueba 2,
--   con quien mas clientes repiten.
-- -------------------------------------------------------------
SELECT e.nombre_empleado,
       COUNT(*)                        AS pedidos,
       COUNT(DISTINCT p.cedula_cliente) AS clientes_distintos
FROM Pedido p
JOIN Empleado e ON e.cedula = p.cedula_empleado
GROUP BY e.cedula, e.nombre_empleado
ORDER BY e.nombre_empleado;


-- -------------------------------------------------------------
-- Q4 · WHERE + HAVING (filtran cosas distintas)
-- PREGUNTA: ¿Que dias vendimos mas de $100.000 en pedidos pagados?
-- RESULTADO: 5 de 7 dias: 9 nov $142.500; 10 nov $128.500; 11 nov $134.500;
--   13 nov $158.000; 14 nov $302.000. Quedan fuera el 12 ($99.000) y el 15 ($47.500).
-- QUE VEO: el 14 de nov (sabado) vendio $302.000 con 5 pedidos pagados, casi el
--   doble que el siguiente mejor dia.
-- QUE SIGNIFICA: el sabado parece concentrar la demanda, pero en los datos hay
--   un solo sabado. El 15 de nov es bajo porque sus pedidos desde las 6:30 p. m.
--   siguen en cola y aun no estan pagados.
-- QUE DECIDO: reforzar el personal el proximo sabado y comprobar si el patron se repite.
-- WHERE filtra FILAS antes de agrupar (solo pedidos pagados); HAVING filtra
-- GRUPOS despues de sumar (solo dias con mas de $100.000).
-- -------------------------------------------------------------
SELECT pe.fecha_creacion::date AS dia,
       COUNT(DISTINCT pe.id_pedido) AS pedidos_pagados,
       SUM(
           (d.cantidad_detallepedido * d.precio_unitario) +
           COALESCE((
               SELECT SUM(pd.precio_ajuste)
               FROM PersonalizacionDetalle pd
               WHERE pd.id_detalle = d.id_detalle
           ), 0)
       ) AS ventas
FROM Pedido pe
JOIN DetallePedido d ON d.id_pedido = pe.id_pedido
WHERE pe.id_estado_pedido = 5                                   -- Pagado
GROUP BY pe.fecha_creacion::date
HAVING SUM(
           (d.cantidad_detallepedido * d.precio_unitario) +
           COALESCE((
               SELECT SUM(pd.precio_ajuste)
               FROM PersonalizacionDetalle pd
               WHERE pd.id_detalle = d.id_detalle
           ), 0)
       ) > 100000
ORDER BY dia;


-- -------------------------------------------------------------
-- Q5 · Una tasa o porcentaje (denominador nombrado, division sin truncar)
-- PREGUNTA: ¿Que porcentaje de las reservas esta pendiente?
-- RESULTADO: 4 pendientes de 12 reservas = 33,33 %.
-- DENOMINADOR: todas las reservas registradas (12), incluidas las canceladas
--   y las de clientes que no asistieron.
-- QUE VEO: una de cada tres reservas esta pendiente.
-- QUE SIGNIFICA: son reservas aun sin confirmar; las 4 son de los dias 18 al 21 de nov.
-- QUE DECIDO: confirmar por telefono esas 4 reservas antes de su fecha.
-- Division sin truncar: 100.0 fuerza decimales. La columna division_entera muestra
-- el error: 4 / 12 entre enteros da 0.
-- -------------------------------------------------------------
SELECT COUNT(*) FILTER (WHERE r.id_estado_reserva = 1)                          AS pendientes,
       COUNT(*)                                                                  AS total_reservas,
       ROUND(100.0 * COUNT(*) FILTER (WHERE r.id_estado_reserva = 1) / COUNT(*), 2) AS pct_pendientes,
       (COUNT(*) FILTER (WHERE r.id_estado_reserva = 1) / COUNT(*))              AS division_entera
FROM Reserva r;


-- -------------------------------------------------------------
-- Q6 · INNER JOIN de cuatro tablas (sin multiplicar filas)
-- PREGUNTA: ¿Cual fue el ingrediente mas usado en ventas pagadas, medido en gramos?
-- RESULTADO: Carne molida de res 3.600 g; Papa criolla 1.900 g; Filete de res
--   crudo 1.750 g.
-- QUE VEO: la carne molida lidera con 3.600 g, casi el doble que la papa criolla.
-- QUE SIGNIFICA: la carne molida alimenta la hamburguesa (el plato mas vendido,
--   Q2) y la bandeja ejecutiva; cualquier falta de este ingrediente frena las ventas.
-- QUE DECIDO: revisar que el stock minimo de carne molida (2.000 g) cubra el
--   tiempo de reposicion, porque en 7 dias se consumieron 3.600 g.
-- Solo se comparan ingredientes en gramos: sumar g con ml o unidades no tiene sentido.
-- La demostracion de que el join no multiplica filas va justo debajo.
-- -------------------------------------------------------------
SELECT i.nombre_ingrediente, i.unidad_medida, SUM(-m.cantidad_movimiento) AS usado
FROM MovimientoInventario m
JOIN DetallePedido d ON d.id_detalle     = m.id_detalle
JOIN Pedido       pe ON pe.id_pedido     = d.id_pedido
JOIN Ingrediente  i  ON i.id_ingrediente = m.id_ingrediente
WHERE m.tipo_movimiento = 'SALIDA_VENTA'
  AND pe.id_estado_pedido = 5                                   -- Pagado
  AND i.unidad_medida = 'g'
GROUP BY i.id_ingrediente, i.nombre_ingrediente, i.unidad_medida
ORDER BY usado DESC, i.nombre_ingrediente
LIMIT 3;

-- Q6-verificacion: filas del join (todas las unidades) vs salidas de venta de
-- pedidos pagados contadas sin el join a Ingrediente. Deben ser iguales (117 y 117).
SELECT COUNT(*) AS filas_del_join
FROM MovimientoInventario m
JOIN DetallePedido d ON d.id_detalle     = m.id_detalle
JOIN Pedido       pe ON pe.id_pedido     = d.id_pedido
JOIN Ingrediente  i  ON i.id_ingrediente = m.id_ingrediente
WHERE m.tipo_movimiento = 'SALIDA_VENTA' AND pe.id_estado_pedido = 5;

SELECT COUNT(*) AS salidas_de_pedidos_pagados
FROM MovimientoInventario m
JOIN DetallePedido d ON d.id_detalle = m.id_detalle
JOIN Pedido pe       ON pe.id_pedido = d.id_pedido
WHERE m.tipo_movimiento = 'SALIDA_VENTA' AND pe.id_estado_pedido = 5;


-- -------------------------------------------------------------
-- Q7 · LEFT JOIN + GROUP BY (con ceros visibles)
-- PREGUNTA: ¿Cuantos pedidos ha tenido cada mesa, incluidas las que no tienen ninguno?
-- RESULTADO: mesas 7 y 8 con 0 pedidos; mesa 5: 4; mesa 4: 5; mesa 6: 5;
--   mesa 2: 6; mesa 3: 6; mesa 1: 7.
-- QUE VEO: la mesa 7 (4 puestos, en limpieza) y la mesa 8 (10 puestos, fuera de
--   servicio) no han vendido nada; la mesa 5, de 8 puestos, es la que menos
--   vende entre las que si se usan.
-- QUE SIGNIFICA: la mesa de 10 puestos esta parada y las mesas grandes se
--   aprovechan menos que las chicas.
-- QUE DECIDO: poner de nuevo en servicio la mesa 8 o retirarla del plano; no
--   dejarla parada, porque Q1 muestra que hoy no hay mesa libre para grupos grandes.
-- COUNT(p.id_pedido) cuenta pedidos reales (0 si no hay). La columna
-- filas_con_count_estrella muestra el error: COUNT(*) da 1 para las mesas sin
-- pedidos porque cuenta la fila de la mesa, no la del pedido.
-- -------------------------------------------------------------
SELECT m.numero_mesa, e.nombre_estado_mesa,
       COUNT(p.id_pedido) AS pedidos,
       COUNT(*)           AS filas_con_count_estrella
FROM Mesa m
JOIN EstadoMesa e ON e.id_estado_mesa = m.id_estado_mesa
LEFT JOIN Pedido p ON p.id_mesa = m.id_mesa
GROUP BY m.id_mesa, m.numero_mesa, e.nombre_estado_mesa
ORDER BY pedidos, m.numero_mesa;


-- -------------------------------------------------------------
-- Q8 · NOT EXISTS
-- PREGUNTA: ¿Que ingredientes con stock no estan en ninguna receta?
-- RESULTADO: Aguacate Hass (28 unidades, 2 veces como adicional) y Cilantro
--   fresco (800 g, 0 veces).
-- QUE VEO: dos ingredientes con stock que ningun plato consume en su receta.
-- QUE SIGNIFICA: el vacio quiere decir stock inmovilizado: el aguacate solo
--   sale cuando un cliente lo pide como adicional (2 veces) y el cilantro nunca
--   salio. Ambos son perecederos.
-- QUE DECIDO: dejar de comprar cilantro hasta que una receta lo use, y comprar
--   aguacate solo en la cantidad que piden los adicionales.
-- -------------------------------------------------------------
SELECT i.nombre_ingrediente, i.stock_actual, i.unidad_medida,
       (SELECT COUNT(*)
        FROM PersonalizacionDetalle pd
        WHERE pd.id_ingrediente = i.id_ingrediente
          AND pd.tipo_accion = 'AGREGAR') AS veces_como_adicional
FROM Ingrediente i
WHERE NOT EXISTS (SELECT 1 FROM Receta r WHERE r.id_ingrediente = i.id_ingrediente)
ORDER BY i.nombre_ingrediente;


-- -------------------------------------------------------------
-- Q9 · Subconsulta correlacionada (usa p.fecha_creacion de la consulta de afuera)
-- PREGUNTA: Por cada pedido en cola (pendiente o en preparacion), ¿cuantos
--   pedidos en cola se crearon antes que el suyo?
-- RESULTADO: pedido 29: 0; 30: 1; 31: 2; 32: 3; 33: 4.
-- QUE VEO: hay 5 pedidos en cola y el ultimo tiene 4 por delante.
-- QUE SIGNIFICA: la espera de un pedido crece con los que tiene por delante. Es
--   una medida de cola, no de minutos: el modelo no guarda la capacidad de la
--   cocina, por eso no se estima un tiempo.
-- QUE DECIDO: avisar a las mesas con tres o mas pedidos por delante (hoy el 32
--   y el 33). El umbral de tres es una decision del equipo.
-- -------------------------------------------------------------
SELECT p.id_pedido, p.fecha_creacion,
       (SELECT COUNT(*)
        FROM Pedido q
        WHERE q.id_estado_pedido IN (1, 2)                      -- Pendiente, En preparacion
          AND q.fecha_creacion < p.fecha_creacion) AS pedidos_por_delante
FROM Pedido p
WHERE p.id_estado_pedido IN (1, 2)
ORDER BY p.fecha_creacion;


-- -------------------------------------------------------------
-- Q10 · ALL (la misma respuesta con MAX)
-- PREGUNTA: ¿Que platos cuestan mas que TODAS las bebidas?
-- RESULTADO: 7 platos: Brownie $9.000, Ensalada $12.000, Sopa de Lentejas
--   $15.000, Carne Asada $18.000, Pollo a la Plancha $19.000, Bandeja
--   Ejecutiva $21.000 y Hamburguesa $24.000.
-- QUE VEO: 7 de los 12 platos superan a la bebida mas cara (Jugo de Naranja,
--   $7.000); las porciones de Arroz ($4.500) y Papas ($6.000) quedan por debajo.
-- QUE SIGNIFICA: la comida "de plato" siempre cuesta mas que cualquier
--   bebida, pero las dos porciones valen menos que un jugo.
-- QUE DECIDO: armar los combos plato + bebida solo sobre esos 7 platos y dejar
--   fuera del combo las dos porciones.
-- -------------------------------------------------------------
SELECT nombre_plato, precio_base
FROM Plato
WHERE precio_base > ALL (SELECT precio_base FROM Plato WHERE id_categoria_plato = 4)   -- 4 = Bebidas
ORDER BY precio_base, nombre_plato;

-- Q10-verificacion: la misma respuesta con MAX (7 filas, mismos platos).
SELECT nombre_plato, precio_base
FROM Plato
WHERE precio_base > (SELECT MAX(precio_base) FROM Plato WHERE id_categoria_plato = 4)
ORDER BY precio_base, nombre_plato;

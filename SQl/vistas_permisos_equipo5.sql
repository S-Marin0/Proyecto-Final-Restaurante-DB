-- =============================================================
-- VISTAS Y PERMISOS - SISTEMA DE GESTION DE RESTAURANTE (PostgreSQL)
-- Equipo 5 - Bases de Datos
-- Archivo 3 de 6. Corre sin errores despues de esquema_ y poblar_, y se puede
-- volver a correr (esquema_equipo5.sql borra las vistas antes que las tablas).
-- Las pruebas de rechazo (SET ROLE, REVOKE) estan en pruebas_equipo5.sql, P16 a P19:
-- aqui los errores no son el resultado esperado.
-- Sin contrasenas en este archivo: los roles rol_* son NOLOGIN (se prueban con SET ROLE)
-- y los usuarios de la aplicacion (app_consulta, app_operacion) se crean sin clave;
-- la clave se pone aparte, a mano, y nunca se entrega (ver LEEME de la aplicacion).
-- =============================================================

-- -------------------------------------------------------------
-- 1. VISTAS
-- -------------------------------------------------------------

-- Vista 1 (junta 5 tablas para una pregunta frecuente: "como va cada pedido
-- y cuanto suma"). El total no se guarda en Pedido: se calcula desde las
-- lineas (cantidad x precio_unitario + recargos de personalizacion).
CREATE OR REPLACE VIEW v_pedido_publico AS
SELECT p.id_pedido,
       p.fecha_creacion,
       m.numero_mesa,
       ep.nombre_estado_pedido,
       e.nombre_empleado AS mesero,
       c.nombre_cliente,
       COALESCE((
         SELECT SUM(d.cantidad_detallepedido * d.precio_unitario
                    + COALESCE((SELECT SUM(pd.precio_ajuste)
                                FROM PersonalizacionDetalle pd
                                WHERE pd.id_detalle = d.id_detalle), 0))
         FROM DetallePedido d
         WHERE d.id_pedido = p.id_pedido), 0) AS total_pedido
FROM Pedido p
JOIN Mesa m          ON m.id_mesa = p.id_mesa
JOIN EstadoPedido ep ON ep.id_estado_pedido = p.id_estado_pedido
JOIN Empleado e      ON e.cedula = p.cedula_empleado
LEFT JOIN Cliente c  ON c.cedula_cliente = p.cedula_cliente;

-- Vista 2 (oculta columnas sensibles): del cliente NO se exponen cedula,
-- telefono ni email; solo nombre, fecha de registro y estado.
CREATE OR REPLACE VIEW v_cliente_publico AS
SELECT c.nombre_cliente,
       c.fecha_registro,
       ec.nombre_estado_cliente
FROM Cliente c
JOIN EstadoCliente ec ON ec.id_estado_cliente = c.id_estado_cliente;

-- Vista 3 (para la pantalla de busqueda): la carta sin ids internos.
CREATE OR REPLACE VIEW v_plato_publico AS
SELECT p.nombre_plato,
       cp.nombre_categoria_plato,
       p.precio_base,
       p.tiempo_preparacion_min,
       ep.nombre_estado_plato
FROM Plato p
JOIN CategoriaPlato cp ON cp.id_categoria_plato = p.id_categoria_plato
JOIN EstadoPlato ep    ON ep.id_estado_plato   = p.id_estado_plato;

-- Vista 4 (para reportes): una fila por linea de pedido, con el importe ya
-- calculado (cantidad x precio_unitario + recargos). La aplicacion agrupa
-- sobre esta vista con GROUP BY / HAVING.
CREATE OR REPLACE VIEW v_linea_pedido AS
SELECT d.id_detalle,
       pe.id_pedido,
       pe.fecha_creacion::date AS dia,
       es.nombre_estado_pedido,
       p.nombre_plato,
       cp.nombre_categoria_plato,
       d.cantidad_detallepedido AS cantidad,
       d.cantidad_detallepedido * d.precio_unitario
         + COALESCE((SELECT SUM(pd.precio_ajuste)
                     FROM PersonalizacionDetalle pd
                     WHERE pd.id_detalle = d.id_detalle), 0) AS importe
FROM DetallePedido d
JOIN Pedido pe          ON pe.id_pedido = d.id_pedido
JOIN EstadoPedido es    ON es.id_estado_pedido = pe.id_estado_pedido
JOIN Plato p            ON p.id_plato = d.id_plato
JOIN CategoriaPlato cp  ON cp.id_categoria_plato = p.id_categoria_plato;

-- -------------------------------------------------------------
-- 2. ROLES (NOLOGIN: no tienen contrasena, se usan con SET ROLE)
-- -------------------------------------------------------------
-- CREATE ROLE no tiene IF NOT EXISTS: el bloque DO lo hace re-ejecutable.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_consulta') THEN
        CREATE ROLE rol_consulta NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_operacion') THEN
        CREATE ROLE rol_operacion NOLOGIN;
    END IF;
END
$$;

-- Usuarios fijos de la aplicacion web (requisito de dos roles). Se crean SIN
-- clave: sin clave nadie puede conectarse con ellos. La clave se pone a mano
-- fuera de este archivo:  ALTER ROLE app_consulta PASSWORD '...';
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_consulta') THEN
        CREATE ROLE app_consulta LOGIN IN ROLE rol_consulta;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_operacion') THEN
        CREATE ROLE app_operacion LOGIN IN ROLE rol_operacion;
    END IF;
END
$$;

-- Para poder ponerse los roles y probarlos con SET ROLE.
GRANT rol_consulta  TO CURRENT_USER;
GRANT rol_operacion TO CURRENT_USER;

-- -------------------------------------------------------------
-- 3. PERMISOS
-- -------------------------------------------------------------
-- Asegurar acceso de lectura al esquema public en PostgreSQL 15+
GRANT USAGE ON SCHEMA public TO rol_consulta, rol_operacion;

-- rol_consulta: solo lee vistas. No tiene ningun permiso sobre las tablas.
GRANT SELECT ON v_pedido_publico, v_cliente_publico, v_plato_publico, v_linea_pedido TO rol_consulta;

-- rol_operacion: atiende pedidos. Lee lo que necesita, crea y modifica pedidos,
-- lineas y personalizaciones, pero NO borra nada ("nada se borra").
GRANT SELECT ON Pedido, DetallePedido, PersonalizacionDetalle, Mesa, Plato,
                Ingrediente, Cliente, Empleado, EstadoPedido TO rol_operacion;
GRANT INSERT, UPDATE ON Pedido, DetallePedido, PersonalizacionDetalle TO rol_operacion;
GRANT USAGE ON SEQUENCE pedido_id_pedido_seq, detallepedido_id_detalle_seq,
                        personalizaciondetalle_id_personalizacion_seq TO rol_operacion;

-- Ampliacion para la aplicacion web.
-- rol_operacion tambien lee las vistas y el resto de tablas que usan sus pantallas.
GRANT SELECT ON v_pedido_publico, v_cliente_publico, v_plato_publico, v_linea_pedido TO rol_operacion;
GRANT SELECT ON Reserva, TipoReserva, EstadoReserva, EstadoMesa, CategoriaPlato,
                EstadoPlato, Menu, Receta, MovimientoInventario TO rol_operacion;
-- Formularios: gestiona la carta (platos) y las reservas. Borrar un plato solo
-- funciona si nunca se vendio (la llave foranea de DetallePedido lo impide);
-- los pedidos y las facturas siguen sin DELETE.
GRANT INSERT, UPDATE, DELETE ON Plato TO rol_operacion;
GRANT INSERT, UPDATE ON Reserva TO rol_operacion;
GRANT UPDATE (id_estado_mesa) ON Mesa TO rol_operacion;
GRANT USAGE ON SEQUENCE plato_id_plato_seq, reserva_id_reserva_seq TO rol_operacion;

"""
DAO de pantalla de detalle con JOINs multiples y LEFT JOIN con ceros (Requisito 4).

Cumple:
  - JOIN de 4 tablas (Q6: consumo de ingredientes en gramos en pedidos pagados:
    MovimientoInventario + DetallePedido + Pedido + Ingrediente).
  - JOIN de 6 tablas (detalle completo de consumo por pedido).
  - LEFT JOIN con ceros visibles (Q7: pedidos por mesa usando COUNT(p.id_pedido),
    mostrando 0 en las mesas 7 y 8 que no tienen pedidos).
"""

import pyodbc
from config.conexion import obtener_cursor
from dao.errores_pg import traducir_error_pg


def consumo_ingredientes_pagados(unidad: str = "g", rol: str = "operacion") -> list[dict]:
    """
    JOIN de 4 tablas (Q6): ingrediente mas usado en ventas pagadas filtrado por unidad.
    Tablas: MovimientoInventario, DetallePedido, Pedido, Ingrediente.
    """
    sql = """
        SELECT i.nombre_ingrediente,
               i.unidad_medida,
               SUM(-m.cantidad_movimiento) AS cantidad_usada,
               i.stock_actual,
               i.stock_minimo
        FROM MovimientoInventario m
        JOIN DetallePedido d ON d.id_detalle     = m.id_detalle
        JOIN Pedido       pe ON pe.id_pedido     = d.id_pedido
        JOIN Ingrediente  i  ON i.id_ingrediente = m.id_ingrediente
        WHERE m.tipo_movimiento = 'SALIDA_VENTA'
          AND pe.id_estado_pedido = 5
          AND i.unidad_medida = ?
        GROUP BY i.id_ingrediente, i.nombre_ingrediente, i.unidad_medida,
                 i.stock_actual, i.stock_minimo
        ORDER BY cantidad_usada DESC, i.nombre_ingrediente ASC
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql, (unidad,))
            columnas = [desc[0] for desc in cur.description]
            return [dict(zip(columnas, fila)) for fila in cur.fetchall()]
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def detalle_pedidos_recientes(limite: int = 20, rol: str = "operacion") -> list[dict]:
    """
    JOIN de 6 tablas: Pedido + Mesa + Cliente + EstadoPedido + DetallePedido + Plato.
    Muestra el detalle de cada linea vendida junto con el recargo de personalizaciones.
    """
    sql = """
        SELECT pe.id_pedido,
               pe.fecha_creacion,
               m.numero_mesa,
               c.nombre_cliente,
               ep.nombre_estado_pedido,
               p.nombre_plato,
               d.cantidad_detallepedido AS cantidad,
               d.precio_unitario,
               (d.cantidad_detallepedido * d.precio_unitario) +
               COALESCE((
                   SELECT SUM(pd.precio_ajuste)
                   FROM PersonalizacionDetalle pd
                   WHERE pd.id_detalle = d.id_detalle
               ), 0) AS valor_linea
        FROM Pedido pe
        JOIN Mesa          m  ON m.id_mesa          = pe.id_mesa
        JOIN Cliente       c  ON c.cedula_cliente   = pe.cedula_cliente
        JOIN EstadoPedido  ep ON ep.id_estado_pedido = pe.id_estado_pedido
        JOIN DetallePedido d  ON d.id_pedido        = pe.id_pedido
        JOIN Plato         p  ON p.id_plato         = d.id_plato
        ORDER BY pe.fecha_creacion DESC, pe.id_pedido DESC, d.id_detalle ASC
        LIMIT ?
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql, (limite,))
            columnas = [desc[0] for desc in cur.description]
            return [dict(zip(columnas, fila)) for fila in cur.fetchall()]
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def pedidos_por_mesa_con_ceros(rol: str = "operacion") -> list[dict]:
    """
    LEFT JOIN + GROUP BY (Q7): lista todas las mesas, incluidas las que tienen 0 pedidos.
    Usa COUNT(p.id_pedido) para que las mesas sin movimiento aparezcan con 0.
    """
    sql = """
        SELECT m.numero_mesa,
               m.capacidad_mesa,
               e.nombre_estado_mesa,
               COUNT(p.id_pedido) AS pedidos
        FROM Mesa m
        JOIN EstadoMesa e ON e.id_estado_mesa = m.id_estado_mesa
        LEFT JOIN Pedido p ON p.id_mesa = m.id_mesa
        GROUP BY m.id_mesa, m.numero_mesa, m.capacidad_mesa, e.nombre_estado_mesa
        ORDER BY pedidos ASC, m.numero_mesa ASC
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql)
            columnas = [desc[0] for desc in cur.description]
            return [dict(zip(columnas, fila)) for fila in cur.fetchall()]
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc

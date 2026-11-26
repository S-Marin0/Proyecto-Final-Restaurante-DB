"""
DAO de pantalla de alertas para el negocio (Requisito 5).

Cumple:
  - Consulta con NOT EXISTS (Q8): ingredientes con existencias que no pertenecen
    a ninguna receta estandar (stock inmovilizado).
  - Subconsulta correlacionada (Q9): pedidos en cola (Pendiente o En preparacion)
    con la cantidad de pedidos creados antes que cada uno.
  - Alerta operativa complementaria: ingredientes por debajo del stock minimo.
"""

import pyodbc
from config.conexion import obtener_cursor
from dao.errores_pg import traducir_error_pg


def ingredientes_sin_receta(rol: str = "operacion") -> list[dict]:
    """
    Q8 (NOT EXISTS): ingredientes con stock que no aparecen en ninguna receta.
    Incluye subconsulta correlacionada para saber cuantas veces salieron como adicional.
    """
    sql = """
        SELECT i.nombre_ingrediente,
               i.stock_actual,
               i.unidad_medida,
               i.ubicacion,
               (SELECT COUNT(*)
                FROM PersonalizacionDetalle pd
                WHERE pd.id_ingrediente = i.id_ingrediente
                  AND pd.tipo_accion = 'AGREGAR') AS veces_como_adicional
        FROM Ingrediente i
        WHERE NOT EXISTS (
            SELECT 1
            FROM Receta r
            WHERE r.id_ingrediente = i.id_ingrediente
        )
        ORDER BY i.nombre_ingrediente ASC
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql)
            columnas = [desc[0] for desc in cur.description]
            return [dict(zip(columnas, fila)) for fila in cur.fetchall()]
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def pedidos_en_cola(rol: str = "operacion") -> list[dict]:
    """
    Q9 (subconsulta correlacionada): por cada pedido en cola (Pendiente=1 o
    En preparacion=2), cuenta cuantos pedidos en cola se crearon antes que el suyo.
    """
    sql = """
        SELECT p.id_pedido,
               p.fecha_creacion,
               m.numero_mesa,
               ep.nombre_estado_pedido,
               (SELECT COUNT(*)
                FROM Pedido q
                WHERE q.id_estado_pedido IN (1, 2)
                  AND q.fecha_creacion < p.fecha_creacion) AS pedidos_por_delante
        FROM Pedido p
        JOIN Mesa m          ON m.id_mesa = p.id_mesa
        JOIN EstadoPedido ep ON ep.id_estado_pedido = p.id_estado_pedido
        WHERE p.id_estado_pedido IN (1, 2)
        ORDER BY p.fecha_creacion ASC, p.id_pedido ASC
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql)
            columnas = [desc[0] for desc in cur.description]
            return [dict(zip(columnas, fila)) for fila in cur.fetchall()]
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def ingredientes_bajo_stock_minimo(rol: str = "operacion") -> list[dict]:
    """Alerta de reposicion: ingredientes cuyo stock actual es menor al minimo."""
    sql = """
        SELECT nombre_ingrediente,
               stock_actual,
               stock_minimo,
               unidad_medida,
               ubicacion
        FROM Ingrediente
        WHERE stock_actual < stock_minimo
        ORDER BY (stock_minimo - stock_actual) DESC, nombre_ingrediente ASC
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql)
            columnas = [desc[0] for desc in cur.description]
            return [dict(zip(columnas, fila)) for fila in cur.fetchall()]
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc

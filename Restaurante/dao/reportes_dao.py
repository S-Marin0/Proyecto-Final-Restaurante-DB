"""
DAO de reportes del negocio (Requisito 3).

Cumple:
  - GROUP BY y HAVING que responden una pregunta del negocio (Q4: dias con ventas
    en pedidos pagados por encima de un umbral configurable).
  - Tasas/porcentajes con division real (100.0) y denominador explicito en pantalla:
      * Porcentaje de pedidos pagados sobre el total de pedidos (v_pedido_publico, ambos roles).
      * Porcentaje de reservas pendientes sobre el total de reservas (Q5, rol_operacion).
"""

from decimal import Decimal
import pyodbc
from config.conexion import obtener_cursor
from dao.errores_pg import traducir_error_pg


def ventas_diarias_por_umbral(monto_minimo: Decimal, rol: str = "consulta") -> list[dict]:
    """
    Responde: ¿Que dias vendimos mas de $monto_minimo en pedidos pagados?
    WHERE filtra filas antes de agrupar (solo pedidos en estado Pagado).
    HAVING filtra grupos despues de sumar (solo dias que superan el umbral).
    """
    sql = """
        SELECT dia,
               COUNT(DISTINCT id_pedido) AS pedidos_pagados,
               SUM(cantidad)             AS unidades_vendidas,
               SUM(importe)              AS ventas
        FROM v_linea_pedido
        WHERE nombre_estado_pedido = 'Pagado'
        GROUP BY dia
        HAVING SUM(importe) > ?
        ORDER BY dia ASC
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql, (monto_minimo,))
            columnas = [desc[0] for desc in cur.description]
            return [dict(zip(columnas, fila)) for fila in cur.fetchall()]
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def top_platos_pagados(limite: int = 5, rol: str = "consulta") -> list[dict]:
    """
    Platos mas vendidos en pedidos pagados (Q2 sobre v_linea_pedido) con
    desempate explicito: unidades DESC, ingresos DESC, nombre_plato ASC.
    """
    sql = """
        SELECT nombre_plato,
               nombre_categoria_plato,
               SUM(cantidad) AS unidades,
               SUM(importe)  AS ingresos
        FROM v_linea_pedido
        WHERE nombre_estado_pedido = 'Pagado'
        GROUP BY nombre_plato, nombre_categoria_plato
        ORDER BY unidades DESC, ingresos DESC, nombre_plato ASC
        LIMIT ?
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql, (limite,))
            columnas = [desc[0] for desc in cur.description]
            return [dict(zip(columnas, fila)) for fila in cur.fetchall()]
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def tasa_pedidos_pagados(rol: str = "consulta") -> dict:
    """
    Calcula el porcentaje de pedidos pagados sobre todos los pedidos registrados.
    Usa 100.0 para evitar division entera truncada.
    """
    sql = """
        SELECT COUNT(*) FILTER (WHERE nombre_estado_pedido = 'Pagado') AS pagados,
               COUNT(*) AS total_pedidos,
               COALESCE(
                   ROUND(100.0 * COUNT(*) FILTER (WHERE nombre_estado_pedido = 'Pagado')
                         / NULLIF(COUNT(*), 0), 2),
                   0.00
               ) AS pct_pagados
        FROM v_pedido_publico
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql)
            fila = cur.fetchone()
            return {
                "pagados": fila[0],
                "total_pedidos": fila[1],
                "pct_pagados": fila[2],
            }
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def tasa_reservas_pendientes(rol: str = "operacion") -> dict:
    """
    Q5: ¿Que porcentaje de las reservas esta pendiente?
    Denominador: todas las reservas registradas (incluidas canceladas y no asistio).
    Requiere acceso a la tabla Reserva (disponible para rol_operacion).
    """
    sql = """
        SELECT COUNT(*) FILTER (WHERE r.id_estado_reserva = 1) AS pendientes,
               COUNT(*) AS total_reservas,
               COALESCE(
                   ROUND(100.0 * COUNT(*) FILTER (WHERE r.id_estado_reserva = 1)
                         / NULLIF(COUNT(*), 0), 2),
                   0.00
               ) AS pct_pendientes
        FROM Reserva r
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql)
            fila = cur.fetchone()
            return {
                "pendientes": fila[0],
                "total_reservas": fila[1],
                "pct_pendientes": fila[2],
            }
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc

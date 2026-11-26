"""
DAO de lectura directa sobre vistas del esquema y pruebas de permisos (Requisitos 6 y 7).

Cumple:
  - Requisito 6: Lee directamente de las vistas v_pedido_publico y v_cliente_publico
    (no de las tablas base), dejando claro en el codigo la fuente consultada.
  - Requisito 7: Incluye acciones reales contra PostgreSQL para demostrar que
    app_consulta es rechazado directamente por la base de datos (SQLSTATE 42501)
    al intentar leer tablas base o escribir datos, y que app_operacion es rechazado
    al intentar borrar ventas en Pedido.
"""

import pyodbc
from config.conexion import obtener_cursor
from dao.errores_pg import traducir_error_pg


def obtener_platos_destacados(limite: int = 6, rol: str = "consulta") -> list[dict]:
    """
    Obtiene platos disponibles destacados desde v_plato_publico para la
    portada publica del cliente (sin exponer metricas internas de ventas).
    """
    sql = """
        SELECT nombre_plato,
               nombre_categoria_plato,
               precio_base,
               tiempo_preparacion_min,
               nombre_estado_plato
        FROM v_plato_publico
        WHERE nombre_estado_plato = 'Disponible'
        ORDER BY precio_base DESC, nombre_plato ASC
        LIMIT ?
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql, (limite,))
            columnas = [desc[0] for desc in cur.description]
            return [dict(zip(columnas, fila)) for fila in cur.fetchall()]
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def obtener_resumen_inicio(rol: str = "consulta") -> dict:
    """
    Obtiene indicadores generales del restaurante usando unicamente vistas
    (v_plato_publico y v_pedido_publico) para que funcione en ambos roles.
    """
    sql_platos = """
        SELECT COUNT(*) AS total_platos,
               COUNT(*) FILTER (WHERE nombre_estado_plato = 'Disponible') AS disponibles
        FROM v_plato_publico
    """
    sql_pedidos = """
        SELECT COUNT(*) AS total_pedidos,
               COUNT(*) FILTER (WHERE nombre_estado_pedido = 'Pagado') AS pagados,
               COUNT(*) FILTER (WHERE nombre_estado_pedido IN ('Pendiente', 'En preparación')) AS en_curso,
               COALESCE(SUM(total_pedido) FILTER (WHERE nombre_estado_pedido = 'Pagado'), 0) AS ventas_pagadas
        FROM v_pedido_publico
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql_platos)
            fp = cur.fetchone()
            cur.execute(sql_pedidos)
            fpe = cur.fetchone()
            return {
                "total_platos": fp[0],
                "platos_disponibles": fp[1],
                "total_pedidos": fpe[0],
                "pedidos_pagados": fpe[1],
                "pedidos_en_curso": fpe[2],
                "ventas_pagadas": fpe[3],
            }
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def listar_pedidos_desde_vista(rol: str = "consulta") -> list[dict]:
    """Lee pedidos directamente desde la vista v_pedido_publico."""
    sql = """
        SELECT id_pedido,
               fecha_creacion,
               numero_mesa,
               nombre_estado_pedido,
               mesero,
               nombre_cliente,
               total_pedido
        FROM v_pedido_publico
        ORDER BY fecha_creacion DESC, id_pedido DESC
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql)
            columnas = [desc[0] for desc in cur.description]
            return [dict(zip(columnas, fila)) for fila in cur.fetchall()]
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def listar_clientes_desde_vista(rol: str = "consulta") -> list[dict]:
    """
    Lee clientes directamente desde la vista v_cliente_publico.
    Esta vista oculta columnas sensibles (cedula_cliente, telefono y email).
    """
    sql = """
        SELECT nombre_cliente,
               fecha_registro,
               nombre_estado_cliente
        FROM v_cliente_publico
        ORDER BY nombre_cliente ASC
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql)
            columnas = [desc[0] for desc in cur.description]
            return [dict(zip(columnas, fila)) for fila in cur.fetchall()]
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def probar_lectura_tabla_cliente(rol: str) -> dict:
    """
    Prueba real de permisos (Requisito 7): intenta leer datos sensibles
    directamente de la tabla base Cliente.
    - Con app_consulta: PostgreSQL rechaza con SQLSTATE 42501.
    - Con app_operacion: PostgreSQL permite la lectura.
    """
    sql = """
        SELECT cedula_cliente, nombre_cliente, telefono, email
        FROM Cliente
        ORDER BY cedula_cliente ASC
        LIMIT 3
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql)
            filas = cur.fetchall()
            return {
                "permitido": True,
                "mensaje": (
                    f"PostgreSQL permitio leer la tabla base Cliente con el rol '{rol}' "
                    f"({len(filas)} filas de muestra leidas)."
                ),
            }
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def probar_escritura_tabla_plato(rol: str) -> dict:
    """
    Prueba real de permisos de escritura (Requisito 7): intenta ejecutar un
    UPDATE inofensivo sobre Plato (WHERE id_plato = -1, no modifica filas reales).
    PostgreSQL evalua el privilegio UPDATE antes del WHERE:
    - Con app_consulta: rechazado por PostgreSQL con SQLSTATE 42501.
    - Con app_operacion: permitido (0 filas afectadas).
    """
    sql = "UPDATE Plato SET precio_base = precio_base WHERE id_plato = ?"
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql, (-1,))
            return {
                "permitido": True,
                "mensaje": (
                    f"PostgreSQL permitio la sentencia UPDATE sobre Plato con el rol '{rol}' "
                    f"(prueba sin cambios reales: {cur.rowcount} filas afectadas)."
                ),
            }
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def probar_borrado_tabla_pedido(rol: str) -> dict:
    """
    Prueba real de la regla 'las ventas son intocables' (P18): intenta borrar
    un pedido. Tanto rol_consulta como rol_operacion carecen de DELETE sobre Pedido,
    asi que PostgreSQL rechaza ambos con SQLSTATE 42501.
    """
    sql = "DELETE FROM Pedido WHERE id_pedido = ?"
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql, (1,))
            return {
                "permitido": True,
                "mensaje": f"Se afectaron {cur.rowcount} filas.",
            }
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc

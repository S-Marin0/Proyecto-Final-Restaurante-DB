"""
DAO de busqueda de platos sobre v_plato_publico (Requisito 2).

Cumple:
  - WHERE con parametro escrito por el usuario (sentencia preparada con ?).
  - ORDER BY con desempate explicito (precio_base DESC, nombre_plato ASC).
  - Funciona tanto para app_consulta como para app_operacion.
"""

import pyodbc
from config.conexion import obtener_cursor
from dao.errores_pg import traducir_error_pg


def listar_categorias(rol: str = "consulta") -> list[str]:
    """Obtiene las categorias disponibles desde la vista v_plato_publico."""
    sql = """
        SELECT DISTINCT nombre_categoria_plato
        FROM v_plato_publico
        ORDER BY nombre_categoria_plato ASC
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql)
            return [fila[0] for fila in cur.fetchall()]
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def buscar_platos(texto: str = "", categoria: str = "", rol: str = "consulta") -> list[dict]:
    """
    Busca platos en v_plato_publico por coincidencia parcial en el nombre
    y categoria opcional, ordenados por precio descendente con desempate
    alfabetico por nombre del plato.
    """
    patron = f"%{texto.strip()}%"
    cat_limpia = categoria.strip()

    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            if cat_limpia:
                sql = """
                    SELECT nombre_plato,
                           nombre_categoria_plato,
                           precio_base,
                           tiempo_preparacion_min,
                           nombre_estado_plato
                    FROM v_plato_publico
                    WHERE nombre_plato ILIKE ?
                      AND nombre_categoria_plato = ?
                    ORDER BY precio_base DESC, nombre_plato ASC
                """
                cur.execute(sql, (patron, cat_limpia))
            else:
                sql = """
                    SELECT nombre_plato,
                           nombre_categoria_plato,
                           precio_base,
                           tiempo_preparacion_min,
                           nombre_estado_plato
                    FROM v_plato_publico
                    WHERE nombre_plato ILIKE ?
                    ORDER BY precio_base DESC, nombre_plato ASC
                """
                cur.execute(sql, (patron,))
            columnas = [desc[0] for desc in cur.description]
            return [dict(zip(columnas, fila)) for fila in cur.fetchall()]
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc

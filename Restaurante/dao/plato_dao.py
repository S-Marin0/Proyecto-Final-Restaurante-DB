"""
DAO de gestion de platos: INSERT, UPDATE y DELETE con traduccion de excepciones (Requisito 8).

Cumple:
  - INSERT, UPDATE y DELETE desde la aplicacion web, informando cuantas filas se afectaron.
  - Traduce violaciones de UNIQUE (23505), CHECK (23514) y FOREIGN KEY (23503)
    mediante dao/errores_pg.py sin mostrar errores tecnicos al usuario.
  - 100% sentencias preparadas con ? (pyodbc).
"""

from decimal import Decimal
import pyodbc
from config.conexion import obtener_cursor
from dao.errores_pg import traducir_error_pg


def listar_platos(rol: str = "operacion") -> list[dict]:
    """Lista los platos con su categoria, estado y menu para gestion operativa."""
    sql = """
        SELECT p.id_plato,
               p.nombre_plato,
               p.descripcion_plato,
               p.precio_base,
               p.tiempo_preparacion_min,
               p.es_personalizable,
               p.id_categoria_plato,
               cp.nombre_categoria_plato,
               p.id_estado_plato,
               ep.nombre_estado_plato,
               p.id_menu,
               m.nombre_menu
        FROM Plato p
        JOIN CategoriaPlato cp ON cp.id_categoria_plato = p.id_categoria_plato
        JOIN EstadoPlato    ep ON ep.id_estado_plato    = p.id_estado_plato
        JOIN Menu           m  ON m.id_menu             = p.id_menu
        ORDER BY p.id_plato ASC
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql)
            columnas = [desc[0] for desc in cur.description]
            return [dict(zip(columnas, fila)) for fila in cur.fetchall()]
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def listar_catalogos_plato(rol: str = "operacion") -> dict:
    """Obtiene categorias, estados y menus para los formularios de Plato."""
    sql_cat = "SELECT id_categoria_plato, nombre_categoria_plato FROM CategoriaPlato ORDER BY id_categoria_plato"
    sql_est = "SELECT id_estado_plato, nombre_estado_plato FROM EstadoPlato ORDER BY id_estado_plato"
    sql_men = "SELECT id_menu, nombre_menu FROM Menu ORDER BY id_menu"

    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql_cat)
            categorias = [{"id": f[0], "nombre": f[1]} for f in cur.fetchall()]
            cur.execute(sql_est)
            estados = [{"id": f[0], "nombre": f[1]} for f in cur.fetchall()]
            cur.execute(sql_men)
            menus = [{"id": f[0], "nombre": f[1]} for f in cur.fetchall()]
            return {"categorias": categorias, "estados": estados, "menus": menus}
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def crear_plato(
    nombre_plato: str,
    descripcion_plato: str,
    precio_base: Decimal,
    tiempo_preparacion_min: int,
    es_personalizable: bool,
    id_categoria_plato: int,
    id_estado_plato: int,
    id_menu: int,
    rol: str = "operacion",
) -> int:
    """
    Inserta un nuevo plato en Plato y devuelve la cantidad de filas afectadas.
    Puede disparar:
      - UNIQUE (23505): plato_nombre_plato_key si el nombre ya existe.
      - CHECK  (23514): si precio_base < 0 o tiempo_preparacion_min < 0.
      - FK     (23503): si categoria, estado o menu no existen.
    """
    sql = """
        INSERT INTO Plato (
            nombre_plato,
            descripcion_plato,
            precio_base,
            tiempo_preparacion_min,
            es_personalizable,
            id_categoria_plato,
            id_estado_plato,
            id_menu
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(
                sql,
                (
                    nombre_plato.strip(),
                    descripcion_plato.strip() or None,
                    precio_base,
                    tiempo_preparacion_min,
                    es_personalizable,
                    id_categoria_plato,
                    id_estado_plato,
                    id_menu,
                ),
            )
            return cur.rowcount
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def actualizar_plato(
    id_plato: int,
    nombre_plato: str,
    precio_base: Decimal,
    tiempo_preparacion_min: int,
    id_estado_plato: int,
    rol: str = "operacion",
) -> int:
    """Actualiza datos de un plato existente y devuelve cuantas filas se afectaron."""
    sql = """
        UPDATE Plato
        SET nombre_plato = ?,
            precio_base = ?,
            tiempo_preparacion_min = ?,
            id_estado_plato = ?
        WHERE id_plato = ?
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(
                sql,
                (
                    nombre_plato.strip(),
                    precio_base,
                    tiempo_preparacion_min,
                    id_estado_plato,
                    id_plato,
                ),
            )
            return cur.rowcount
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def eliminar_plato(id_plato: int, rol: str = "operacion") -> int:
    """
    Elimina un plato por id y devuelve cuantas filas se afectaron.
    Si el plato ya tiene pedidos en DetallePedido o recetas en Receta,
    PostgreSQL lo rechaza por ON DELETE RESTRICT (SQLSTATE 23503 -> FOREIGN_KEY).
    """
    sql = "DELETE FROM Plato WHERE id_plato = ?"
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql, (id_plato,))
            return cur.rowcount
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc

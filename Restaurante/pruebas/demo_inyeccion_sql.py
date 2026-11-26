"""
DEMOSTRACION DE INYECCION SQL (Requisito 10) — ARCHIVO DE PRUEBA APARTE.

Este script NO forma parte del servidor web ni se importa desde app.py.
Su unico proposito es demostrar la diferencia entre:
  1) Una consulta armada por concatenacion (VULNERABLE a ' OR '1'='1), y
  2) Una sentencia preparada con marcador ? de pyodbc (SEGURA: el texto viaja como dato).

Ejecucion desde la carpeta Restaurante/:
    python pruebas/demo_inyeccion_sql.py
"""

import sys
from pathlib import Path

# Agregar la carpeta Restaurante/ al path para reutilizar config/conexion.py
_CARPETA_APP = Path(__file__).resolve().parent.parent
if str(_CARPETA_APP) not in sys.path:
    sys.path.insert(0, str(_CARPETA_APP))

from config.conexion import ErrorConexionBD, obtener_cursor


def buscar_plato_concatenado_MAL(texto: str) -> tuple[str, list]:
    """
    MAL: el texto del usuario se concatena y pasa a ser parte del codigo SQL.
    Si texto = "' OR '1'='1", la condicion WHERE siempre es verdadera y expone toda la vista.
    """
    sql_mala = (
        "SELECT nombre_plato, nombre_categoria_plato, precio_base "
        "FROM v_plato_publico "
        "WHERE nombre_plato = '" + texto + "' "
        "ORDER BY nombre_plato"
    )
    with obtener_cursor(rol="consulta", autocommit=True) as (_, cur):
        cur.execute(sql_mala)
        return sql_mala, cur.fetchall()


def buscar_plato_preparado_BIEN(texto: str) -> tuple[str, list]:
    """
    BIEN: el texto del usuario viaja por separado como dato en un marcador ?.
    PostgreSQL/ODBC nunca interpreta "' OR '1'='1" como SQL, sino como un texto literal.
    """
    sql_buena = (
        "SELECT nombre_plato, nombre_categoria_plato, precio_base "
        "FROM v_plato_publico "
        "WHERE nombre_plato = ? "
        "ORDER BY nombre_plato"
    )
    with obtener_cursor(rol="consulta", autocommit=True) as (_, cur):
        cur.execute(sql_buena, (texto,))
        return sql_buena, cur.fetchall()


def imprimir_resultados(titulo: str, sentencia: str, parametro: str | None, filas: list) -> None:
    print("=" * 72)
    print(titulo)
    print("-" * 72)
    print("Sentencia SQL:")
    print(f"  {sentencia}")
    if parametro is not None:
        print(f"Parametro enlazado (?): {parametro!r}")
    print(f"Filas devueltas: {len(filas)}")
    for fila in filas:
        print(f"  - {fila[0]} | {fila[1]} | ${fila[2]}")
    print()


def main() -> None:
    entrada_normal = "Hamburguesa Clásica"
    entrada_ataque = "' OR '1'='1"

    try:
        print("\n>>> CASO 1: Entrada normal ->", repr(entrada_normal))
        sql, filas = buscar_plato_preparado_BIEN(entrada_normal)
        imprimir_resultados("PREPARADA (BIEN) con entrada normal", sql, entrada_normal, filas)

        print(">>> CASO 2: Entrada maliciosa ->", repr(entrada_ataque))
        sql_mala, filas_malas = buscar_plato_concatenado_MAL(entrada_ataque)
        imprimir_resultados("1) CONCATENADA (MAL - VULNERABLE)", sql_mala, None, filas_malas)

        sql_buena, filas_buenas = buscar_plato_preparado_BIEN(entrada_ataque)
        imprimir_resultados("2) PREPARADA (BIEN - SEGURA)", sql_buena, entrada_ataque, filas_buenas)

        print("CONCLUSION:")
        print(
            f"  Con la entrada {entrada_ataque!r}, la consulta concatenada devolvio "
            f"{len(filas_malas)} filas (toda la carta), mientras que la sentencia preparada "
            f"devolvio {len(filas_buenas)} filas porque la trato como un texto literal."
        )
    except ErrorConexionBD as exc:
        print(f"[ERROR DE CONEXION] {exc}")


if __name__ == "__main__":
    main()

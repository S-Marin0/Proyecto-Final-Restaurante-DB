"""
DAO transaccional de reservas + mesas y regla de negocio de la Seccion B.2 (Requisito 9).

Cumple:
  - Regla que el esquema no alcanza a vigilar (Seccion B.2 del Avance 2):
      1) cantidad_personas de una reserva <= capacidad_mesa de la mesa.
      2) Dos reservas activas (no canceladas) de la misma mesa no pueden
         solaparse en el tiempo, usando duracion_horas de TipoReserva.
  - Transaccion que toca dos tablas (Reserva y Mesa) con autocommit=False:
      * Paso 1: INSERT INTO Reserva (...)
      * Paso 2: UPDATE Mesa SET id_estado_mesa = ...
      * COMMIT si ambos pasos salen bien; ROLLBACK si algo falla a la mitad.
  - Modo de demostracion "forzar_fallo=True": despues de insertar la reserva en el Paso 1,
    el Paso 2 intenta asignar un id_estado_mesa inexistente (9999), provocando una
    violacion real de llave foranea en PostgreSQL que dispara el ROLLBACK y deja
    los conteos intactos (nada queda a medias).
"""

import pyodbc
from config.conexion import obtener_cursor
from dao.errores_pg import ErrorNegocioBD, traducir_error_pg


ESTADO_MESA_RESERVADA = 3
ESTADO_RESERVA_PENDIENTE = 1
ESTADO_RESERVA_CANCELADA = 4
ESTADO_MESA_INVALIDO_FALLO = 9999


def listar_reservas(rol: str = "operacion") -> list[dict]:
    """Lista las reservas registradas junto con cliente, mesa, tipo y estado."""
    sql = """
        SELECT r.id_reserva,
               r.fecha_hora_inicio,
               r.cantidad_personas,
               c.cedula_cliente,
               c.nombre_cliente,
               m.numero_mesa,
               m.capacidad_mesa,
               t.nombre_tipo,
               t.duracion_horas,
               er.nombre_estado_reserva
        FROM Reserva r
        JOIN Cliente       c  ON c.cedula_cliente    = r.cedula_cliente
        JOIN Mesa          m  ON m.id_mesa           = r.id_mesa
        JOIN TipoReserva   t  ON t.id_tipo_reserva   = r.id_tipo_reserva
        JOIN EstadoReserva er ON er.id_estado_reserva = r.id_estado_reserva
        ORDER BY r.fecha_hora_inicio DESC, r.id_reserva DESC
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql)
            columnas = [desc[0] for desc in cur.description]
            return [dict(zip(columnas, fila)) for fila in cur.fetchall()]
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def listar_catalogos_reserva(rol: str = "operacion") -> dict:
    """Obtiene clientes, mesas (con capacidad y estado actual) y tipos de reserva."""
    sql_clientes = """
        SELECT cedula_cliente, nombre_cliente
        FROM Cliente
        ORDER BY cedula_cliente ASC
    """
    sql_mesas = """
        SELECT m.id_mesa, m.numero_mesa, m.capacidad_mesa,
               m.id_estado_mesa, em.nombre_estado_mesa
        FROM Mesa m
        JOIN EstadoMesa em ON em.id_estado_mesa = m.id_estado_mesa
        ORDER BY m.numero_mesa ASC
    """
    sql_tipos = """
        SELECT id_tipo_reserva, nombre_tipo, duracion_horas, costo_adicional
        FROM TipoReserva
        ORDER BY id_tipo_reserva ASC
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(sql_clientes)
            clientes = [{"cedula": f[0], "nombre": f[1]} for f in cur.fetchall()]

            cur.execute(sql_mesas)
            mesas = [
                {
                    "id_mesa": f[0],
                    "numero_mesa": f[1],
                    "capacidad_mesa": f[2],
                    "id_estado_mesa": f[3],
                    "nombre_estado_mesa": f[4],
                }
                for f in cur.fetchall()
            ]

            cur.execute(sql_tipos)
            tipos = [
                {
                    "id_tipo_reserva": f[0],
                    "nombre_tipo": f[1],
                    "duracion_horas": f[2],
                    "costo_adicional": f[3],
                }
                for f in cur.fetchall()
            ]
            return {"clientes": clientes, "mesas": mesas, "tipos": tipos}
    except pyodbc.Error as exc:
        raise traducir_error_pg(exc) from exc


def _leer_estado_control(cur, id_mesa: int) -> dict:
    """Lee total de reservas y estado actual de la mesa para comparar ANTES y DESPUES."""
    cur.execute("SELECT COUNT(*) FROM Reserva")
    total_reservas = cur.fetchone()[0]

    cur.execute(
        """
        SELECT m.numero_mesa, m.capacidad_mesa, em.nombre_estado_mesa
        FROM Mesa m
        JOIN EstadoMesa em ON em.id_estado_mesa = m.id_estado_mesa
        WHERE m.id_mesa = ?
        """,
        (id_mesa,),
    )
    fila_mesa = cur.fetchone()
    if not fila_mesa:
        return {
            "total_reservas": total_reservas,
            "numero_mesa": None,
            "capacidad_mesa": None,
            "estado_mesa": None,
        }
    return {
        "total_reservas": total_reservas,
        "numero_mesa": fila_mesa[0],
        "capacidad_mesa": fila_mesa[1],
        "estado_mesa": fila_mesa[2],
    }


def _validar_capacidad(antes: dict, cantidad_personas: int) -> None:
    if cantidad_personas > antes["capacidad_mesa"]:
        raise ErrorNegocioBD("REGLA_NEGOCIO", "...capacidad...")

def _obtener_tipo(cur, id_tipo_reserva: int) -> tuple:
    cur.execute(SQL_TIPO, (id_tipo_reserva,))
    fila = cur.fetchone()
    if not fila:
        raise ErrorNegocioBD("FOREIGN_KEY", "El tipo de reserva no existe.", sqlstate="23503")
    return fila  # (nombre_tipo, duracion_horas)

def _validar_sin_solapamiento(cur, id_mesa, fecha, duracion, antes) -> None:
    cur.execute(SQL_SOLAPAMIENTO, (id_mesa, ESTADO_RESERVA_CANCELADA, fecha, duracion, fecha))
    conflicto = cur.fetchone()
    if conflicto:
        raise ErrorNegocioBD("REGLA_NEGOCIO", "...se cruza con la reserva...")

def _insertar_reserva(cur, cedula, id_mesa, id_tipo, fecha, personas) -> int:
    cur.execute(SQL_INSERT_RESERVA, (fecha, personas, cedula, id_mesa, id_tipo,
                                     ESTADO_RESERVA_PENDIENTE))
    return cur.rowcount

def _actualizar_mesa(cur, id_mesa, estado_destino) -> int:
    cur.execute(SQL_UPDATE_MESA, (estado_destino, id_mesa))
    return cur.rowcount

def registrar_reserva_transaccion(...):
    with obtener_cursor(rol=rol, autocommit=False) as (conn, cur):
        cur.execute("SELECT 1 FROM Mesa WHERE id_mesa = ? FOR UPDATE", (id_mesa,))
        antes = _leer_estado_control(cur, id_mesa)

        _validar_capacidad(antes, cantidad_personas)
        nombre_tipo, duracion = _obtener_tipo(cur, id_tipo_reserva)
        _validar_sin_solapamiento(cur, id_mesa, fecha_hora_inicio, duracion, antes)

        filas_reserva = _insertar_reserva(cur, cedula_cliente, id_mesa,
                                          id_tipo_reserva, fecha_hora_inicio, cantidad_personas)
        try:
            filas_mesa = _actualizar_mesa(cur, id_mesa, estado_destino)
        except pyodbc.Error as exc:
            conn.rollback()
            ...
        conn.commit()


# def registrar_reserva_transaccion(
#     cedula_cliente: str,
#     id_mesa: int,
#     id_tipo_reserva: int,
#     fecha_hora_inicio: str,
#     cantidad_personas: int,
#     forzar_fallo: bool = False,
#     rol: str = "operacion",
# ) -> dict:
#     """
#     Ejecuta en una sola transaccion:
#       0) Valida la regla de negocio de la Seccion B.2 (capacidad y no solapamiento).
#       1) INSERT INTO Reserva (Tabla 1).
#       2) UPDATE Mesa SET id_estado_mesa = 3 (Tabla 2) — o 9999 si forzar_fallo=True.
#       3) COMMIT si todo salio bien; ROLLBACK si algo falla en el paso 2.
#     """
#     sql_tipo = "SELECT nombre_tipo, duracion_horas FROM TipoReserva WHERE id_tipo_reserva = ?"
#     sql_solapamiento = """
#         SELECT r.id_reserva,
#                r.fecha_hora_inicio,
#                t.nombre_tipo,
#                t.duracion_horas
#         FROM Reserva r
#         JOIN TipoReserva t ON t.id_tipo_reserva = r.id_tipo_reserva
#         WHERE r.id_mesa = ?
#           AND r.id_estado_reserva <> ?
#           AND r.fecha_hora_inicio < CAST(? AS TIMESTAMP) + CAST(? AS NUMERIC) * INTERVAL '1 hour'
#           AND CAST(? AS TIMESTAMP) < r.fecha_hora_inicio + t.duracion_horas * INTERVAL '1 hour'
#         ORDER BY r.fecha_hora_inicio ASC
#         LIMIT 1
#     """
#     sql_insert_reserva = """
#         INSERT INTO Reserva (
#             fecha_hora_inicio,
#             cantidad_personas,
#             cedula_cliente,
#             id_mesa,
#             id_tipo_reserva,
#             id_estado_reserva
#         )
#         VALUES (CAST(? AS TIMESTAMP), ?, ?, ?, ?, ?)
#     """
#     sql_update_mesa = """
#         UPDATE Mesa
#         SET id_estado_mesa = ?
#         WHERE id_mesa = ?
#     """


#     try:
#         with obtener_cursor(rol=rol, autocommit=False) as (conn, cur):
#             # Fotografia ANTES de la transaccion
#             antes = _leer_estado_control(cur, id_mesa)
#             if antes["numero_mesa"] is None:
#                 raise ErrorNegocioBD("FOREIGN_KEY", "La mesa seleccionada no existe.", sqlstate="23503")

#             if cantidad_personas <= 0:
#                 raise ErrorNegocioBD(
#                     "CHECK",
#                     "La cantidad de personas de la reserva debe ser mayor que cero.",
#                     sqlstate="23514",
#                 )

#             # ------------------------------------------------------------------
#             # REGLA DE NEGOCIO DE LA SECCION B.2 (que el esquema no vigila solo)
#             # Parte 1: cantidad_personas <= capacidad_mesa
#             # ------------------------------------------------------------------
#             if cantidad_personas > antes["capacidad_mesa"]:
#                 raise ErrorNegocioBD(
#                     "REGLA_NEGOCIO",
#                     f"Regla de negocio (capacidad): la mesa {antes['numero_mesa']} tiene capacidad "
#                     f"para {antes['capacidad_mesa']} personas y la reserva solicita {cantidad_personas}. "
#                     "Seleccione una mesa mas grande o reduzca el numero de comensales.",
#                 )

#             # Obtener duracion del tipo de reserva
#             cur.execute(sql_tipo, (id_tipo_reserva,))
#             fila_tipo = cur.fetchone()
#             if not fila_tipo:
#                 raise ErrorNegocioBD("FOREIGN_KEY", "El tipo de reserva seleccionado no existe.", sqlstate="23503")
#             nombre_tipo, duracion_horas = fila_tipo[0], fila_tipo[1]

#             # ------------------------------------------------------------------
#             # REGLA DE NEGOCIO DE LA SECCION B.2 (que el esquema no vigila solo)
#             # Parte 2: no solapar reservas activas de la misma mesa
#             # ------------------------------------------------------------------
#             cur.execute(
#                 sql_solapamiento,
#                 (
#                     id_mesa,
#                     ESTADO_RESERVA_CANCELADA,
#                     fecha_hora_inicio,
#                     duracion_horas,
#                     fecha_hora_inicio,
#                 ),
#             )
#             conflicto = cur.fetchone()
#             if conflicto:
#                 raise ErrorNegocioBD(
#                     "REGLA_NEGOCIO",
#                     f"Regla de negocio (no solapamiento): la mesa {antes['numero_mesa']} ya tiene la "
#                     f"reserva #{conflicto[0]} ({conflicto[2]}, {conflicto[3]} h) iniciando el "
#                     f"{conflicto[1]}. El horario solicitado ({fecha_hora_inicio}, {duracion_horas} h) "
#                     "se cruza con esa reserva.",
#                 )

#             # ------------------------------------------------------------------
#             # TRANSACCION MULTI-TABLA (Reserva + Mesa)
#             # ------------------------------------------------------------------
#             # Paso 1: insertar en Reserva
#             cur.execute(
#                 sql_insert_reserva,
#                 (
#                     fecha_hora_inicio,
#                     cantidad_personas,
#                     cedula_cliente,
#                     id_mesa,
#                     id_tipo_reserva,
#                     ESTADO_RESERVA_PENDIENTE,
#                 ),
#             )
#             filas_reserva = cur.rowcount

#             # Paso 2: actualizar estado de la Mesa (o forzar fallo real de FK en BD)
#             estado_destino = ESTADO_MESA_INVALIDO_FALLO if forzar_fallo else ESTADO_MESA_RESERVADA
#             try:
#                 cur.execute(sql_update_mesa, (estado_destino, id_mesa))
#                 filas_mesa = cur.rowcount
#             except pyodbc.Error as exc_paso2:
#                 # Fallo en el Paso 2 despues de haber insertado la Reserva en el Paso 1 -> ROLLBACK
#                 conn.rollback()
#                 despues_rollback = _leer_estado_control(cur, id_mesa)
#                 error_traducido = traducir_error_pg(exc_paso2)
#                 return {
#                     "resultado": "ROLLBACK",
#                     "mensaje": (
#                         f"Paso 1 ejecutado (INSERT en Reserva: {filas_reserva} fila), pero el Paso 2 "
#                         f"(UPDATE en Mesa) fallo en PostgreSQL: {error_traducido}. "
#                         "Se ejecuto ROLLBACK automatico: la reserva se deshizo y nada quedo a medias."
#                     ),
#                     "filas_reserva": filas_reserva,
#                     "filas_mesa": 0,
#                     "nombre_tipo": nombre_tipo,
#                     "duracion_horas": duracion_horas,
#                     "antes": antes,
#                     "despues": despues_rollback,
#                 }

#             # Ambos pasos exitosos -> COMMIT
#             conn.commit()
#             despues_commit = _leer_estado_control(cur, id_mesa)
#             return {
#                 "resultado": "COMMIT",
#                 "mensaje": (
#                     f"Transaccion confirmada (COMMIT): se inserto {filas_reserva} reserva "
#                     f"({nombre_tipo}, {duracion_horas} h) y se actualizo {filas_mesa} mesa "
#                     f"(Mesa {antes['numero_mesa']} -> {despues_commit['estado_mesa']})."
#                 ),
#                 "filas_reserva": filas_reserva,
#                 "filas_mesa": filas_mesa,
#                 "nombre_tipo": nombre_tipo,
#                 "duracion_horas": duracion_horas,
#                 "antes": antes,
#                 "despues": despues_commit,
#             }
#     except pyodbc.Error as exc:
#         raise traducir_error_pg(exc) from exc

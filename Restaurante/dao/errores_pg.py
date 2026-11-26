"""
Traduccion de excepciones de PostgreSQL/ODBC a mensajes de negocio (Requisitos 7 y 8).

En pyodbc contra psqlODBC:
  - exc.args[0] contiene el SQLSTATE de 5 caracteres:
      * 23505 -> unique_violation       (UNIQUE / PRIMARY KEY)
      * 23514 -> check_violation        (CHECK)
      * 23503 -> foreign_key_violation  (FOREIGN KEY / ON DELETE RESTRICT)
      * 23502 -> not_null_violation     (NOT NULL)
      * 42501 -> insufficient_privilege (permisos de rol en PostgreSQL)
      * 08xxx / HYTxx                   (caida de conexion / timeout)
  - exc.args[1] contiene el detalle del motor, incluido el nombre de la restriccion.

Este modulo evita mostrar errores tecnicos crudos al usuario del negocio.
"""

import pyodbc
from config.conexion import ErrorConexionBD


class ErrorNegocioBD(Exception):
    """Error traducido a lenguaje de negocio (UNIQUE, CHECK, FK, NOT NULL o regla de app)."""

    def __init__(self, tipo: str, mensaje: str, sqlstate: str = ""):
        super().__init__(mensaje)
        self.tipo = tipo          # 'UNIQUE', 'CHECK', 'FOREIGN_KEY', 'NOT_NULL', 'REGLA_NEGOCIO'
        self.mensaje = mensaje
        self.sqlstate = sqlstate


class ErrorPermisoBD(Exception):
    """Error cuando PostgreSQL rechaza una operacion por permisos del rol (SQLSTATE 42501)."""

    def __init__(self, mensaje: str, sqlstate: str = "42501"):
        super().__init__(mensaje)
        self.mensaje = mensaje
        self.sqlstate = sqlstate


def traducir_error_pg(exc: pyodbc.Error) -> Exception:
    """
    Convierte una excepcion pyodbc.Error en ErrorNegocioBD, ErrorPermisoBD
    o ErrorConexionBD con un mensaje comprensible para el usuario del negocio.
    """
    sqlstate = str(exc.args[0]) if len(exc.args) >= 1 else ""
    detalle = str(exc.args[1]).lower() if len(exc.args) >= 2 else str(exc).lower()

    # 1. Errores de conexion / base caida o dormida
    if sqlstate.startswith("08") or sqlstate.startswith("HYT") or "connection" in detalle and "closed" in detalle:
        return ErrorConexionBD(
            "Se perdio la comunicacion con PostgreSQL (la base puede estar dormida o caída). "
            "Intente nuevamente en unos segundos."
        )

    # 2. Permiso denegado por el rol de PostgreSQL (Requisito 7)
    if sqlstate == "42501" or "permission denied" in detalle:
        return ErrorPermisoBD(
            "Acceso rechazado por PostgreSQL (SQLSTATE 42501): el usuario/rol seleccionado "
            "no tiene permiso en la base de datos para ejecutar esta operacion.",
            sqlstate="42501",
        )

    # 3. Violacion de UNIQUE / PRIMARY KEY (Requisito 8)
    if sqlstate == "23505" or "duplicate key" in detalle:
        if "plato_nombre_plato_key" in detalle:
            msg = "Ya existe un plato con ese mismo nombre en la carta. Escriba un nombre diferente."
        elif "mesa_numero_mesa_key" in detalle:
            msg = "Ya existe una mesa registrada con ese numero."
        elif "menu_nombre_menu_key" in detalle:
            msg = "Ya existe un menu con ese mismo nombre."
        elif "uq_receta_plato_ingrediente" in detalle:
            msg = "Ese ingrediente ya esta incluido en la receta de este plato."
        else:
            msg = "Ya existe un registro con ese mismo valor unico. Verifique que no este duplicado."
        return ErrorNegocioBD("UNIQUE", msg, sqlstate="23505")

    # 4. Violacion de CHECK (Requisito 8)
    if sqlstate == "23514" or "check constraint" in detalle:
        if "precio_base" in detalle:
            msg = "El precio base del plato no puede ser negativo. Ingrese un valor igual o mayor a $0."
        elif "tiempo_preparacion_min" in detalle:
            msg = "El tiempo de preparacion no puede ser negativo. Ingrese 0 o mas minutos."
        elif "cantidad_personas" in detalle:
            msg = "La cantidad de personas de la reserva debe ser mayor que cero."
        elif "stock_actual" in detalle:
            msg = "La operacion dejaria el stock del ingrediente en negativo."
        elif "chk_ingrediente_unidad" in detalle:
            msg = "La unidad de medida del ingrediente solo puede ser 'g', 'ml' o 'unidad'."
        elif "chk_movimiento_signo" in detalle:
            msg = "El signo del movimiento de inventario no corresponde a su tipo (venta negativa, compra positiva)."
        else:
            msg = "Uno de los valores ingresados incumple las reglas de rango o dominio del negocio."
        return ErrorNegocioBD("CHECK", msg, sqlstate="23514")

    # 5. Violacion de FOREIGN KEY (Requisito 8)
    if sqlstate == "23503" or "foreign key" in detalle:
        if "detallepedido_id_plato_fkey" in detalle or "receta_id_plato_fkey" in detalle:
            msg = (
                "No se puede eliminar este plato porque ya tiene pedidos registrados o forma parte "
                "de una receta activa. En su lugar, cambie su estado a 'Descontinuado'."
            )
        elif "plato_id_categoria_plato_fkey" in detalle:
            msg = "La categoria de plato seleccionada no existe en el catalogo del restaurante."
        elif "plato_id_estado_plato_fkey" in detalle:
            msg = "El estado de plato seleccionado no existe en el catalogo del restaurante."
        elif "plato_id_menu_fkey" in detalle:
            msg = "El menu seleccionado no existe en el sistema."
        elif "reserva_cedula_cliente_fkey" in detalle:
            msg = "El cliente indicado no esta registrado en el sistema."
        elif "reserva_id_mesa_fkey" in detalle:
            msg = "La mesa seleccionada no existe en el plano del restaurante."
        elif "reserva_id_tipo_reserva_fkey" in detalle:
            msg = "El tipo de reserva seleccionado no existe."
        elif "mesa_id_estado_mesa_fkey" in detalle:
            msg = "El estado asignado a la mesa no existe en el catalogo de estados."
        elif "factura_id_pedido_fkey" in detalle:
            msg = "No se puede eliminar un pedido que ya tiene factura emitida."
        else:
            msg = (
                "La operacion hace referencia a un registro inexistente o intenta borrar un dato "
                "que esta siendo utilizado por otros registros del negocio."
            )
        return ErrorNegocioBD("FOREIGN_KEY", msg, sqlstate="23503")

    # 6. Violacion de NOT NULL
    if sqlstate == "23502" or "null value in column" in detalle:
        return ErrorNegocioBD(
            "NOT_NULL",
            "Faltan datos obligatorios para completar la operacion. Revise todos los campos requeridos.",
            sqlstate="23502",
        )

    # 7. Cualquier otro error de datos no previsto (sin exponer traza tecnica)
    return ErrorNegocioBD(
        "OTRO",
        "No fue posible completar la operacion en la base de datos. Verifique los datos ingresados.",
        sqlstate=sqlstate,
    )

"""
Capa de conexion ODBC hacia PostgreSQL (Requisito 1 y Requisito 7).

- Lee la configuracion desde variables de entorno o desde un archivo externo ".env"
  (nunca guarda cadenas de conexion ni contrasenas en el codigo fuente).
- Se conecta mediante pyodbc usando el controlador ODBC de PostgreSQL (Unidad 6).
- Soporta los dos usuarios fijos de la base:
    * "consulta"  -> app_consulta  (miembro de rol_consulta: solo lectura de vistas)
    * "operacion" -> app_operacion (miembro de rol_operacion: tablas operativas, sin DELETE en ventas)
- Garantiza el cierre explicito de cursores y conexiones en bloques finally.
- Si la base esta caida, dormida o sin configurar, lanza ErrorConexionBD controlada
  para que la pagina web informe el problema sin romperse.
"""

from contextlib import contextmanager
import os
from pathlib import Path
import pyodbc

try:
    from dotenv import load_dotenv
except ModuleNotFoundError:
    def load_dotenv(ruta_env: Path) -> None:
        """Lector minimo de archivos .env si python-dotenv no esta instalado."""
        if not ruta_env.is_file():
            return
        for linea in ruta_env.read_text(encoding="utf-8").splitlines():
            linea = linea.strip()
            if not linea or linea.startswith("#") or "=" not in linea:
                continue
            clave, valor = linea.split("=", 1)
            clave = clave.strip()
            valor = valor.strip().strip('"').strip("'")
            os.environ.setdefault(clave, valor)

# Cargar archivo .env externo si existe (en Restaurante/.env o en la raiz)
_CARPETA_APP = Path(__file__).resolve().parent.parent
load_dotenv(_CARPETA_APP / ".env")
load_dotenv(_CARPETA_APP.parent / ".env")


ROLES_VALIDOS = ("consulta", "operacion")


class ErrorConexionBD(Exception):
    """Error controlado cuando la base de datos esta caida, dormida o mal configurada."""


def _obtener_credenciales_rol(rol: str) -> tuple[str, str]:
    """Devuelve (usuario, contrasena) desde variables de entorno para el rol elegido."""
    if rol not in ROLES_VALIDOS:
        raise ErrorConexionBD(f"Rol no reconocido: '{rol}'. Use 'consulta' u 'operacion'.")

    if rol == "consulta":
        usuario = os.getenv("DB_USER_CONSULTA", "app_consulta").strip()
        clave = os.getenv("DB_PASS_CONSULTA", "").strip()
        var_clave = "DB_PASS_CONSULTA"
    else:
        usuario = os.getenv("DB_USER_OPERACION", "app_operacion").strip()
        clave = os.getenv("DB_PASS_OPERACION", "").strip()
        var_clave = "DB_PASS_OPERACION"

    if not clave:
        raise ErrorConexionBD(
            f"Falta configurar la variable de entorno {var_clave} en el archivo .env "
            f"(copie .env.example a .env y complete las credenciales)."
        )

    return usuario, clave


def construir_cadena_odbc(rol: str = "consulta") -> str:
    """Arma la cadena de conexion ODBC sin exponer contrasenas en codigo."""
    driver = os.getenv("ODBC_DRIVER", "PostgreSQL Unicode(x64)").strip()
    host = os.getenv("DB_HOST", "").strip()
    port = os.getenv("DB_PORT", "5432").strip()
    database = os.getenv("DB_NAME", "").strip()
    sslmode = os.getenv("DB_SSLMODE", "require").strip()

    if not host or not database:
        raise ErrorConexionBD(
            "Faltan DB_HOST o DB_NAME en el archivo .env. "
            "Copie Restaurante/.env.example como Restaurante/.env y configure la conexion."
        )

    usuario, clave = _obtener_credenciales_rol(rol)

    # BoolsAsChar=0 hace que psqlODBC devuelva BOOLEAN de PostgreSQL como True/False
    return (
        f"DRIVER={{{driver}}};"
        f"SERVER={host};"
        f"PORT={port};"
        f"DATABASE={database};"
        f"UID={usuario};"
        f"PWD={clave};"
        f"SSLMode={sslmode};"
        f"BoolsAsChar=0;"
    )


def abrir_conexion(rol: str = "consulta", autocommit: bool = True) -> pyodbc.Connection:
    """Abre una nueva conexion ODBC con el rol indicado y timeout controlado."""
    cadena = construir_cadena_odbc(rol)
    timeout = int(os.getenv("DB_TIMEOUT", "6"))

    try:
        return pyodbc.connect(cadena, autocommit=autocommit, timeout=timeout)
    except pyodbc.InterfaceError as exc:
        texto = str(exc).lower()
        if "driver" in texto or "im002" in texto:
            driver = os.getenv("ODBC_DRIVER", "PostgreSQL Unicode(x64)")
            raise ErrorConexionBD(
                f"No se encontro el controlador ODBC '{driver}'. "
                "Verifique que psqlODBC este instalado y que ODBC_DRIVER coincida en .env."
            ) from exc
        raise ErrorConexionBD(
            "No fue posible comunicarse con la base de datos a traves del controlador ODBC. "
            "Verifique que PostgreSQL/Neon este activo y accesible."
        ) from exc
    except pyodbc.OperationalError as exc:
        texto = str(exc).lower()
        if "password authentication failed" in texto or "28p01" in texto:
            raise ErrorConexionBD(
                f"Autenticacion rechazada por PostgreSQL para el rol '{rol}'. "
                "Revise el usuario y contrasena configurados en .env."
            ) from exc
        raise ErrorConexionBD(
            "La base de datos PostgreSQL no responde (puede estar apagada, dormida o sin red). "
            "Intente nuevamente en unos segundos."
        ) from exc
    except pyodbc.Error as exc:
        raise ErrorConexionBD(
            "Error al abrir la conexion ODBC con PostgreSQL. Revise la configuracion en .env."
        ) from exc


@contextmanager
def obtener_cursor(rol: str = "consulta", autocommit: bool = True):
    """
    Administrador de contexto que abre conexion y cursor, y garantiza cerrarlos
    siempre al terminar (Requisito 1: cierra todo lo que abre).

    Si autocommit=False (transacciones), ante cualquier excepcion ejecuta rollback
    antes de cerrar los recursos.
    """
    conn = abrir_conexion(rol=rol, autocommit=autocommit)
    cur = conn.cursor()
    try:
        yield conn, cur
    except Exception:
        if not autocommit:
            try:
                conn.rollback()
            except pyodbc.Error:
                pass
        raise
    finally:
        try:
            cur.close()
        except pyodbc.Error:
            pass
        try:
            conn.close()
        except pyodbc.Error:
            pass


def verificar_conexion(rol: str = "consulta") -> dict:
    """
    Prueba la conexion con el rol activo y consulta identidad/version en PostgreSQL.
    Nunca lanza excepcion: retorna un diccionario con el estado para la interfaz.
    """
    try:
        with obtener_cursor(rol=rol, autocommit=True) as (_, cur):
            cur.execute(
                "SELECT current_user, current_database(), "
                "split_part(version(), ' ', 1) || ' ' || split_part(version(), ' ', 2)"
            )
            fila = cur.fetchone()
            return {
                "conectado": True,
                "usuario_bd": fila[0],
                "base_datos": fila[1],
                "version_pg": fila[2],
                "driver": os.getenv("ODBC_DRIVER", "PostgreSQL Unicode(x64)"),
                "mensaje": f"Conectado correctamente como '{fila[0]}' en '{fila[1]}'.",
            }
    except ErrorConexionBD as exc:
        return {
            "conectado": False,
            "usuario_bd": None,
            "base_datos": None,
            "version_pg": None,
            "driver": os.getenv("ODBC_DRIVER", "PostgreSQL Unicode(x64)"),
            "mensaje": str(exc),
        }
    except pyodbc.Error:
        return {
            "conectado": False,
            "usuario_bd": None,
            "base_datos": None,
            "version_pg": None,
            "driver": os.getenv("ODBC_DRIVER", "PostgreSQL Unicode(x64)"),
            "mensaje": "La conexion se interrumpio al consultar el estado de PostgreSQL.",
        }

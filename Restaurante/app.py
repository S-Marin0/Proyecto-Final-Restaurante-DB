"""
Servidor web Flask - Sistema de Gestion de Restaurante (Equipo 5).

Arquitectura de capas:
  Navegador  <-->  Servidor Web (app.py + templates/)
             <-->  Capa de Datos (dao/*.py, SQL a mano con sentencias preparadas)
             <-->  Modulo de Conexion ODBC (config/conexion.py, pyodbc)
             <-->  PostgreSQL (Neon o local)

No contiene SQL directo: todas las sentencias viven en el paquete dao/.
"""

from decimal import Decimal, InvalidOperation
import os
import sys
from pathlib import Path
from flask import Flask, flash, redirect, render_template, request, session, url_for

# Permite ejecutar "python app.py" desde Restaurante/ o "python Restaurante/app.py" desde la raiz
_CARPETA_APP = Path(__file__).resolve().parent
if str(_CARPETA_APP) not in sys.path:
    sys.path.insert(0, str(_CARPETA_APP))

from config.conexion import ErrorConexionBD, ROLES_VALIDOS, verificar_conexion
from dao import alertas_dao, busqueda_dao, detalle_dao, plato_dao, reportes_dao, reserva_dao, vistas_dao
from dao.errores_pg import ErrorNegocioBD, ErrorPermisoBD

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY", "restaurante-equipo5-sesion-local")


# ------------------------------------------------------------------
# Utilidades de formato y sesion de rol (Requisito 7)
# ------------------------------------------------------------------
@app.template_filter("moneda")
def filtro_moneda(valor) -> str:
    """Formatea valores numericos como moneda colombiana (ej. $24.000)."""
    if valor is None:
        return "$0"
    try:
        numero = Decimal(str(valor))
        if numero == numero.to_integral_value():
            return f"${int(numero):,}".replace(",", ".")
        return f"${numero:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
    except (InvalidOperation, ValueError):
        return str(valor)


def rol_actual() -> str:
    """Devuelve el rol fijo seleccionado en sesion ('consulta' por defecto)."""
    rol = session.get("rol_activo", "consulta")
    return rol if rol in ROLES_VALIDOS else "consulta"


@app.context_processor
def inyectar_contexto_global():
    """Expone el rol actual y su etiqueta en todas las plantillas."""
    rol = rol_actual()
    etiqueta_usuario = (
        os.getenv("DB_USER_CONSULTA", "app_consulta")
        if rol == "consulta"
        else os.getenv("DB_USER_OPERACION", "app_operacion")
    )
    return {
        "rol_activo": rol,
        "usuario_bd_esperado": etiqueta_usuario,
        "endpoint_actual": request.endpoint or "",
    }


@app.route("/cambiar-rol", methods=["POST"])
def cambiar_rol():
    """Cambia entre los dos usuarios fijos de la aplicacion (sin login, Req 7)."""
    nuevo_rol = request.form.get("rol", "consulta").strip()
    if nuevo_rol in ROLES_VALIDOS:
        session["rol_activo"] = nuevo_rol
        if nuevo_rol == "consulta":
            flash("Ahora navega como Cliente (app_consulta · vista publica de solo lectura).", "info")
        else:
            flash("Ahora trabaja como Personal de Operacion (app_operacion · panel administrativo).", "info")

    destino = request.form.get("next") or url_for("inicio")
    # Al pasar a modo Cliente desde una pantalla interna, vuelve a la portada del cliente
    rutas_internas = ("/reportes", "/detalle", "/alertas", "/platos", "/reservas")
    if nuevo_rol == "consulta" and any(destino.startswith(r) for r in rutas_internas):
        return redirect(url_for("inicio"))
    return redirect(destino)


# ------------------------------------------------------------------
# Inicio + Estado de conexion (Req 1) + Pruebas de permisos (Req 7)
# ------------------------------------------------------------------
def _cargar_datos_portada(rol: str, estado_bd: dict) -> tuple[dict | None, list[dict]]:
    """Carga platos destacados para Cliente o metricas operativas para Personal."""
    resumen = None
    destacados = []
    if not estado_bd["conectado"]:
        return resumen, destacados
    try:
        if rol == "consulta":
            destacados = vistas_dao.obtener_platos_destacados(limite=6, rol=rol)
        else:
            resumen = vistas_dao.obtener_resumen_inicio(rol=rol)
    except (ErrorConexionBD, ErrorPermisoBD, ErrorNegocioBD):
        pass
    return resumen, destacados


@app.route("/", methods=["GET"])
def inicio():
    rol = rol_actual()
    estado_bd = verificar_conexion(rol=rol)
    resumen, destacados = _cargar_datos_portada(rol, estado_bd)
    return render_template(
        "inicio.html",
        estado_bd=estado_bd,
        resumen=resumen,
        destacados=destacados,
        resultado_permiso=None,
    )


@app.route("/probar-permiso", methods=["POST"])
def probar_permiso():
    """Ejecuta pruebas reales contra PostgreSQL para demostrar el rechazo por rol (Req 7)."""
    rol = rol_actual()
    accion = request.form.get("accion", "")
    estado_bd = verificar_conexion(rol=rol)
    resumen, destacados = _cargar_datos_portada(rol, estado_bd)
    resultado_permiso = None

    try:
        if accion == "leer_cliente":
            res = vistas_dao.probar_lectura_tabla_cliente(rol=rol)
            resultado_permiso = {
                "tipo": "ok",
                "titulo": "Consulta directa a la tabla Cliente",
                "detalle": res["mensaje"],
            }
        elif accion == "escribir_plato":
            res = vistas_dao.probar_escritura_tabla_plato(rol=rol)
            resultado_permiso = {
                "tipo": "ok",
                "titulo": "Modificacion sobre la tabla Plato",
                "detalle": res["mensaje"],
            }
        elif accion == "borrar_pedido":
            res = vistas_dao.probar_borrado_tabla_pedido(rol=rol)
            resultado_permiso = {
                "tipo": "ok",
                "titulo": "Eliminacion sobre la tabla Pedido",
                "detalle": res["mensaje"],
            }
    except ErrorPermisoBD as exc:
        resultado_permiso = {
            "tipo": "rechazo_bd",
            "titulo": f"Operacion rechazada por la base de datos ({exc.sqlstate})",
            "detalle": exc.mensaje,
        }
    except (ErrorConexionBD, ErrorNegocioBD) as exc:
        resultado_permiso = {
            "tipo": "error",
            "titulo": "No se pudo completar la verificacion",
            "detalle": str(exc),
        }

    return render_template(
        "inicio.html",
        estado_bd=estado_bd,
        resumen=resumen,
        destacados=destacados,
        resultado_permiso=resultado_permiso,
    )


# ------------------------------------------------------------------
# Requisito 2: Pantalla de busqueda (WHERE parametrizado + ORDER BY desempate)
# ------------------------------------------------------------------
@app.route("/busqueda", methods=["GET"])
def busqueda():
    rol = rol_actual()
    texto = request.args.get("q", "").strip()
    categoria = request.args.get("categoria", "").strip()
    error_bd = None
    categorias = []
    platos = []

    try:
        categorias = busqueda_dao.listar_categorias(rol=rol)
        platos = busqueda_dao.buscar_platos(texto=texto, categoria=categoria, rol=rol)
    except (ErrorConexionBD, ErrorPermisoBD, ErrorNegocioBD) as exc:
        error_bd = str(exc)

    return render_template(
        "busqueda.html",
        texto=texto,
        categoria=categoria,
        categorias=categorias,
        platos=platos,
        error_bd=error_bd,
    )


# ------------------------------------------------------------------
# Requisito 3: Pantalla de reportes (GROUP BY + HAVING + tasa con denominador)
# ------------------------------------------------------------------
@app.route("/reportes", methods=["GET"])
def reportes():
    rol = rol_actual()
    umbral_raw = request.args.get("umbral", "100000").strip()
    try:
        umbral = Decimal(umbral_raw) if umbral_raw else Decimal("100000")
    except InvalidOperation:
        umbral = Decimal("100000")
        flash("El umbral ingresado no es un numero valido; se uso $100.000 por defecto.", "warning")

    error_bd = None
    dias_ventas = []
    top_platos = []
    tasa_pedidos = None
    tasa_reservas = None
    aviso_reservas = None

    try:
        dias_ventas = reportes_dao.ventas_diarias_por_umbral(monto_minimo=umbral, rol=rol)
        top_platos = reportes_dao.top_platos_pagados(limite=5, rol=rol)
        tasa_pedidos = reportes_dao.tasa_pedidos_pagados(rol=rol)
        try:
            tasa_reservas = reportes_dao.tasa_reservas_pendientes(rol=rol)
        except ErrorPermisoBD as exc:
            aviso_reservas = exc.mensaje
    except (ErrorConexionBD, ErrorPermisoBD, ErrorNegocioBD) as exc:
        error_bd = str(exc)

    return render_template(
        "reportes.html",
        umbral=umbral,
        dias_ventas=dias_ventas,
        top_platos=top_platos,
        tasa_pedidos=tasa_pedidos,
        tasa_reservas=tasa_reservas,
        aviso_reservas=aviso_reservas,
        error_bd=error_bd,
    )


# ------------------------------------------------------------------
# Requisito 4: Pantalla de detalle (JOIN 3+ tablas + LEFT JOIN con ceros)
# ------------------------------------------------------------------
@app.route("/detalle", methods=["GET"])
def detalle():
    rol = rol_actual()
    unidad = request.args.get("unidad", "g").strip()
    if unidad not in ("g", "ml", "unidad"):
        unidad = "g"

    error_bd = None
    error_permiso = None
    consumo = []
    mesas = []
    lineas_pedidos = []

    try:
        consumo = detalle_dao.consumo_ingredientes_pagados(unidad=unidad, rol=rol)
        mesas = detalle_dao.pedidos_por_mesa_con_ceros(rol=rol)
        lineas_pedidos = detalle_dao.detalle_pedidos_recientes(limite=15, rol=rol)
    except ErrorPermisoBD as exc:
        error_permiso = exc.mensaje
    except (ErrorConexionBD, ErrorNegocioBD) as exc:
        error_bd = str(exc)

    return render_template(
        "detalle.html",
        unidad=unidad,
        consumo=consumo,
        mesas=mesas,
        lineas_pedidos=lineas_pedidos,
        error_bd=error_bd,
        error_permiso=error_permiso,
    )


# ------------------------------------------------------------------
# Requisito 5: Pantalla de alertas (NOT EXISTS + subconsulta correlacionada)
# ------------------------------------------------------------------
@app.route("/alertas", methods=["GET"])
def alertas():
    rol = rol_actual()
    error_bd = None
    error_permiso = None
    sin_receta = []
    cola_pedidos = []
    bajo_minimo = []

    try:
        sin_receta = alertas_dao.ingredientes_sin_receta(rol=rol)
        cola_pedidos = alertas_dao.pedidos_en_cola(rol=rol)
        bajo_minimo = alertas_dao.ingredientes_bajo_stock_minimo(rol=rol)
    except ErrorPermisoBD as exc:
        error_permiso = exc.mensaje
    except (ErrorConexionBD, ErrorNegocioBD) as exc:
        error_bd = str(exc)

    return render_template(
        "alertas.html",
        sin_receta=sin_receta,
        cola_pedidos=cola_pedidos,
        bajo_minimo=bajo_minimo,
        error_bd=error_bd,
        error_permiso=error_permiso,
    )


# ------------------------------------------------------------------
# Requisito 6: Pantalla sobre vistas (v_pedido_publico y v_cliente_publico)
# ------------------------------------------------------------------
@app.route("/vistas", methods=["GET"])
def vistas():
    rol = rol_actual()
    error_bd = None
    pedidos_vista = []
    clientes_vista = []

    try:
        pedidos_vista = vistas_dao.listar_pedidos_desde_vista(rol=rol)
        clientes_vista = vistas_dao.listar_clientes_desde_vista(rol=rol)
    except (ErrorConexionBD, ErrorPermisoBD, ErrorNegocioBD) as exc:
        error_bd = str(exc)

    return render_template(
        "vistas.html",
        pedidos_vista=pedidos_vista,
        clientes_vista=clientes_vista,
        error_bd=error_bd,
    )


# ------------------------------------------------------------------
# Requisito 8: Formularios (INSERT, UPDATE, DELETE) y excepciones amigables
# ------------------------------------------------------------------
@app.route("/platos", methods=["GET"])
def platos():
    rol = rol_actual()
    error_bd = None
    error_permiso = None
    lista_platos = []
    catalogos = {"categorias": [], "estados": [], "menus": []}

    try:
        lista_platos = plato_dao.listar_platos(rol=rol)
        catalogos = plato_dao.listar_catalogos_plato(rol=rol)
    except ErrorPermisoBD as exc:
        error_permiso = exc.mensaje
    except (ErrorConexionBD, ErrorNegocioBD) as exc:
        error_bd = str(exc)

    return render_template(
        "platos.html",
        platos=lista_platos,
        catalogos=catalogos,
        error_bd=error_bd,
        error_permiso=error_permiso,
    )


@app.route("/platos/crear", methods=["POST"])
def platos_crear():
    rol = rol_actual()
    nombre = request.form.get("nombre_plato", "").strip()
    descripcion = request.form.get("descripcion_plato", "").strip()
    es_personalizable = request.form.get("es_personalizable") == "on"

    if not nombre:
        flash("El nombre del plato es obligatorio.", "error")
        return redirect(url_for("platos"))

    try:
        precio_base = Decimal(request.form.get("precio_base", "0").strip())
        tiempo_min = int(request.form.get("tiempo_preparacion_min", "15").strip())
        # Campo opcional para facilitar pruebas en vivo de violacion de FOREIGN KEY (ej. 999)
        cat_manual = request.form.get("id_categoria_manual", "").strip()
        id_categoria = int(cat_manual) if cat_manual else int(request.form.get("id_categoria_plato", "1"))
        id_estado = int(request.form.get("id_estado_plato", "1"))
        id_menu = int(request.form.get("id_menu", "1"))
    except (InvalidOperation, ValueError):
        flash("Precio, tiempo o identificadores deben ser valores numericos validos.", "error")
        return redirect(url_for("platos"))

    try:
        filas = plato_dao.crear_plato(
            nombre_plato=nombre,
            descripcion_plato=descripcion,
            precio_base=precio_base,
            tiempo_preparacion_min=tiempo_min,
            es_personalizable=es_personalizable,
            id_categoria_plato=id_categoria,
            id_estado_plato=id_estado,
            id_menu=id_menu,
            rol=rol,
        )
        flash(f"Plato '{nombre}' registrado correctamente. Filas afectadas: {filas}.", "success")
    except ErrorPermisoBD as exc:
        flash(exc.mensaje, "permiso")
    except ErrorNegocioBD as exc:
        flash(f"[{exc.tipo}] {exc.mensaje}", "error")
    except ErrorConexionBD as exc:
        flash(str(exc), "error")

    return redirect(url_for("platos"))


@app.route("/platos/actualizar", methods=["POST"])
def platos_actualizar():
    rol = rol_actual()
    try:
        id_plato = int(request.form.get("id_plato", "0"))
        nombre = request.form.get("nombre_plato", "").strip()
        precio_base = Decimal(request.form.get("precio_base", "0").strip())
        tiempo_min = int(request.form.get("tiempo_preparacion_min", "0").strip())
        id_estado = int(request.form.get("id_estado_plato", "1"))
    except (InvalidOperation, ValueError):
        flash("Datos numericos invalidos al actualizar el plato.", "error")
        return redirect(url_for("platos"))

    if not nombre:
        flash("El nombre del plato no puede quedar vacio.", "error")
        return redirect(url_for("platos"))

    try:
        filas = plato_dao.actualizar_plato(
            id_plato=id_plato,
            nombre_plato=nombre,
            precio_base=precio_base,
            tiempo_preparacion_min=tiempo_min,
            id_estado_plato=id_estado,
            rol=rol,
        )
        flash(f"Plato #{id_plato} actualizado correctamente. Filas afectadas: {filas}.", "success")
    except ErrorPermisoBD as exc:
        flash(exc.mensaje, "permiso")
    except ErrorNegocioBD as exc:
        flash(f"[{exc.tipo}] {exc.mensaje}", "error")
    except ErrorConexionBD as exc:
        flash(str(exc), "error")

    return redirect(url_for("platos"))


@app.route("/platos/eliminar", methods=["POST"])
def platos_eliminar():
    rol = rol_actual()
    try:
        id_plato = int(request.form.get("id_plato", "0"))
    except ValueError:
        flash("Identificador de plato invalido.", "error")
        return redirect(url_for("platos"))

    try:
        filas = plato_dao.eliminar_plato(id_plato=id_plato, rol=rol)
        flash(f"Plato #{id_plato} eliminado correctamente. Filas afectadas: {filas}.", "success")
    except ErrorPermisoBD as exc:
        flash(exc.mensaje, "permiso")
    except ErrorNegocioBD as exc:
        flash(f"[{exc.tipo}] {exc.mensaje}", "error")
    except ErrorConexionBD as exc:
        flash(str(exc), "error")

    return redirect(url_for("platos"))


# ------------------------------------------------------------------
# Requisito 9 + Regla B.2: Transaccion multi-tabla (Reserva + Mesa)
# ------------------------------------------------------------------
@app.route("/reservas", methods=["GET", "POST"])
def reservas():
    rol = rol_actual()
    error_bd = None
    error_permiso = None
    resultado_tx = None
    lista_reservas = []
    catalogos = {"clientes": [], "mesas": [], "tipos": []}

    if request.method == "POST":
        cedula_cliente = request.form.get("cedula_cliente", "").strip()
        fecha_raw = request.form.get("fecha_hora_inicio", "").strip()
        # Convierte "YYYY-MM-DDTHH:MM" (input datetime-local) a "YYYY-MM-DD HH:MM:00"
        fecha_sql = fecha_raw.replace("T", " ")
        if len(fecha_sql) == 16:
            fecha_sql += ":00"
        forzar_fallo = request.form.get("forzar_fallo") == "on"

        try:
            id_mesa = int(request.form.get("id_mesa", "0"))
            id_tipo_reserva = int(request.form.get("id_tipo_reserva", "0"))
            cantidad_personas = int(request.form.get("cantidad_personas", "0"))
        except ValueError:
            flash("Mesa, tipo de reserva y cantidad de personas deben ser enteros.", "error")
            return redirect(url_for("reservas"))

        if not cedula_cliente or not fecha_sql:
            flash("Debe seleccionar cliente y fecha/hora de inicio.", "error")
            return redirect(url_for("reservas"))

        try:
            resultado_tx = reserva_dao.registrar_reserva_transaccion(
                cedula_cliente=cedula_cliente,
                id_mesa=id_mesa,
                id_tipo_reserva=id_tipo_reserva,
                fecha_hora_inicio=fecha_sql,
                cantidad_personas=cantidad_personas,
                forzar_fallo=forzar_fallo,
                rol=rol,
            )
        except ErrorPermisoBD as exc:
            error_permiso = exc.mensaje
        except ErrorNegocioBD as exc:
            flash(f"[{exc.tipo}] {exc.mensaje}", "error")
        except ErrorConexionBD as exc:
            error_bd = str(exc)

    if not error_permiso and not error_bd:
        try:
            lista_reservas = reserva_dao.listar_reservas(rol=rol)
            catalogos = reserva_dao.listar_catalogos_reserva(rol=rol)
        except ErrorPermisoBD as exc:
            error_permiso = exc.mensaje
        except (ErrorConexionBD, ErrorNegocioBD) as exc:
            error_bd = str(exc)

    return render_template(
        "reservas.html",
        reservas=lista_reservas,
        catalogos=catalogos,
        resultado_tx=resultado_tx,
        error_bd=error_bd,
        error_permiso=error_permiso,
    )


if __name__ == "__main__":
    puerto = int(os.getenv("FLASK_PORT", "5000"))
    app.run(host="127.0.0.1", port=puerto, debug=False)

-- =============================================================
-- ESQUEMA - SISTEMA DE GESTION DE RESTAURANTE (PostgreSQL)
-- Equipo 5 - Bases de Datos
-- Archivo 1 de 6 (corre en orden: esquema, poblar, vistas_permisos, consultas)
-- Contiene solo DROP y CREATE; los datos van en poblar_equipo5.sql
-- =============================================================
--
-- POLITICA DE BORRADO (ON DELETE) - decidida FK por FK:
--   RESTRICT  Catalogos (estados, tipos, categorias) y entidades con historia
--             (cliente, empleado, mesa, plato, menu, ingrediente, pedido):
--             no se borra un padre mientras tenga hijos.
--   CASCADE   Partes que no tienen sentido sin su pedido: detalle,
--             personalizacion y novedad.
--   SET NULL  MovimientoInventario.id_detalle: el movimiento de stock se
--             conserva aunque la linea de venta se borre.
--   Receta -> Plato e Ingrediente: RESTRICT; primero se borran las recetas
--             y despues el plato o el ingrediente, nada queda incompleto.
--
-- CAMBIOS FRENTE AL TALLER 9 (B6) - para justificar en la seccion A:
--   * 8 tablas -> 23. Se agregaron Reserva, TipoReserva, Factura, Novedad,
--     Ingrediente, Receta, PersonalizacionDetalle, MovimientoInventario y
--     los catalogos de estado/categoria (EstadoXxx, CategoriaPlato).
--   * Llaves naturales (Numero_mesa, Nombre_plato, Nombre_menu,
--     Nombre_categoria_plato) -> llaves sustitutas id_*. Las cuatro quedan
--     como llaves alternas UNIQUE: Mesa.numero_mesa, Plato.nombre_plato,
--     Menu.nombre_menu y CategoriaPlato.nombre_categoria_plato.
--   * Pedido y DetallePedido: las PK compuestas del Taller 9 pasan a
--     id_pedido e id_detalle (Llaves_candidatas: sin alternas).
--   * Empleado.Nombre_estado_empleado (dependencia transitiva) -> EstadoEmpleado.
--   * Eliminacion de redundancias (BCNF): se eliminaron los atributos derivados
--     Pedido.total y DetallePedido.subtotal para evitar anomalias de
--     actualizacion; se calculan: valor de linea = cantidad_detallepedido *
--     precio_unitario + SUM(precio_ajuste de sus personalizaciones); total del
--     pedido = suma de sus lineas. Se guardan solo las fotos historicas:
--     precio_unitario, precio_ajuste y Factura.monto_total.
--   * Ingrediente.stock_actual se conserva a proposito (es derivable de
--     MovimientoInventario) para poder vigilarlo con CHECK (stock_actual >= 0).
--
-- REGLAS QUE EL ESQUEMA NO VIGILA (las resuelve la aplicacion):
--   * No solapar reservas de una misma mesa (la duracion vive en TipoReserva).
--   * cantidad_personas de una reserva <= capacidad de la mesa (un CHECK
--     no puede comparar columnas de dos tablas).
--
-- NOTA: vistas_permisos_equipo5.sql crea cuatro vistas sobre estas tablas; por eso
-- se borran aqui (DROP VIEW IF EXISTS) antes de los DROP TABLE, para poder volver
-- a correr este archivo. Los roles (rol_consulta, rol_operacion) no dependen de las
-- tablas y se conservan; vistas_permisos_ los crea solo si no existen.

-- ==========================================
-- 0. LIMPIEZA (hijos primero, sin CASCADE)
-- ==========================================
DROP VIEW IF EXISTS v_linea_pedido;
DROP VIEW IF EXISTS v_plato_publico;
DROP VIEW IF EXISTS v_pedido_publico;
DROP VIEW IF EXISTS v_cliente_publico;
DROP TABLE IF EXISTS Novedad;
DROP TABLE IF EXISTS Factura;
DROP TABLE IF EXISTS MovimientoInventario;
DROP TABLE IF EXISTS PersonalizacionDetalle;
DROP TABLE IF EXISTS DetallePedido;
DROP TABLE IF EXISTS Pedido;
DROP TABLE IF EXISTS Receta;
DROP TABLE IF EXISTS Plato;
DROP TABLE IF EXISTS Ingrediente;
DROP TABLE IF EXISTS Reserva;
DROP TABLE IF EXISTS Mesa;
DROP TABLE IF EXISTS Cliente;
DROP TABLE IF EXISTS Empleado;
DROP TABLE IF EXISTS Menu;
DROP TABLE IF EXISTS EstadoPedido;
DROP TABLE IF EXISTS EstadoPlato;
DROP TABLE IF EXISTS CategoriaPlato;
DROP TABLE IF EXISTS EstadoMenu;
DROP TABLE IF EXISTS TipoReserva;
DROP TABLE IF EXISTS EstadoReserva;
DROP TABLE IF EXISTS EstadoMesa;
DROP TABLE IF EXISTS EstadoCliente;
DROP TABLE IF EXISTS EstadoEmpleado;

-- ==========================================
-- 1. CATALOGOS BASE Y ESTADOS
-- ==========================================
CREATE TABLE EstadoEmpleado (
    id_estado_empleado SERIAL PRIMARY KEY,
    nombre_estado_empleado VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE EstadoMesa (
    id_estado_mesa SERIAL PRIMARY KEY,
    nombre_estado_mesa VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE EstadoCliente (
    id_estado_cliente SERIAL PRIMARY KEY,
    nombre_estado_cliente VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE EstadoReserva (
    id_estado_reserva SERIAL PRIMARY KEY,
    nombre_estado_reserva VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE TipoReserva (
    id_tipo_reserva SERIAL PRIMARY KEY,
    nombre_tipo VARCHAR(50) NOT NULL UNIQUE,
    duracion_horas NUMERIC(4, 2) NOT NULL CHECK (duracion_horas > 0),
    costo_adicional NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (costo_adicional >= 0),
    descripcion_tipo_reserva TEXT
);

CREATE TABLE EstadoPedido (
    id_estado_pedido SERIAL PRIMARY KEY,
    nombre_estado_pedido VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE EstadoPlato (
    id_estado_plato SERIAL PRIMARY KEY,
    nombre_estado_plato VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE EstadoMenu (
    id_estado_menu SERIAL PRIMARY KEY,
    nombre_estado_menu VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE CategoriaPlato (
    id_categoria_plato SERIAL PRIMARY KEY,
    nombre_categoria_plato VARCHAR(100) NOT NULL UNIQUE,
    descripcion_categoria_plato TEXT
);

-- ==========================================
-- 2. CLIENTES, EMPLEADOS Y MESAS
-- ==========================================
CREATE TABLE Empleado (
    cedula VARCHAR(20) PRIMARY KEY,
    nombre_empleado VARCHAR(100) NOT NULL,
    rol VARCHAR(50) NOT NULL,
    id_estado_empleado INT NOT NULL
        REFERENCES EstadoEmpleado(id_estado_empleado) ON DELETE RESTRICT
);

CREATE TABLE Mesa (
    id_mesa SERIAL PRIMARY KEY,
    numero_mesa INT NOT NULL UNIQUE CHECK (numero_mesa > 0),
    capacidad_mesa INT NOT NULL CHECK (capacidad_mesa > 0),
    id_estado_mesa INT NOT NULL
        REFERENCES EstadoMesa(id_estado_mesa) ON DELETE RESTRICT
);

CREATE TABLE Cliente (
    cedula_cliente VARCHAR(20) PRIMARY KEY,
    nombre_cliente VARCHAR(100) NOT NULL,
    telefono VARCHAR(20),
    email VARCHAR(100),
    fecha_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_estado_cliente INT NOT NULL
        REFERENCES EstadoCliente(id_estado_cliente) ON DELETE RESTRICT
);

-- ==========================================
-- 3. RESERVAS
-- ==========================================
CREATE TABLE Reserva (
    id_reserva SERIAL PRIMARY KEY,
    fecha_hora_inicio TIMESTAMP NOT NULL,
    cantidad_personas INT NOT NULL CHECK (cantidad_personas > 0),
    cedula_cliente VARCHAR(20) NOT NULL
        REFERENCES Cliente(cedula_cliente) ON DELETE RESTRICT,
    id_mesa INT NOT NULL
        REFERENCES Mesa(id_mesa) ON DELETE RESTRICT,
    id_tipo_reserva INT NOT NULL
        REFERENCES TipoReserva(id_tipo_reserva) ON DELETE RESTRICT,
    id_estado_reserva INT NOT NULL
        REFERENCES EstadoReserva(id_estado_reserva) ON DELETE RESTRICT
);

-- ==========================================
-- 4. MENU, PLATOS, INGREDIENTES Y RECETAS
-- ==========================================
CREATE TABLE Menu (
    id_menu SERIAL PRIMARY KEY,
    nombre_menu VARCHAR(100) NOT NULL UNIQUE,
    id_estado_menu INT NOT NULL
        REFERENCES EstadoMenu(id_estado_menu) ON DELETE RESTRICT
);

CREATE TABLE Plato (
    id_plato SERIAL PRIMARY KEY,
    nombre_plato VARCHAR(100) NOT NULL UNIQUE,
    descripcion_plato TEXT,
    precio_base NUMERIC(10, 2) NOT NULL CHECK (precio_base >= 0),
    tiempo_preparacion_min INT NOT NULL DEFAULT 15 CHECK (tiempo_preparacion_min >= 0),
    es_personalizable BOOLEAN NOT NULL DEFAULT TRUE,
    id_categoria_plato INT NOT NULL
        REFERENCES CategoriaPlato(id_categoria_plato) ON DELETE RESTRICT,
    id_estado_plato INT NOT NULL
        REFERENCES EstadoPlato(id_estado_plato) ON DELETE RESTRICT,
    id_menu INT NOT NULL
        REFERENCES Menu(id_menu) ON DELETE RESTRICT
);

CREATE TABLE Ingrediente (
    id_ingrediente SERIAL PRIMARY KEY,
    nombre_ingrediente VARCHAR(100) NOT NULL,
    unidad_medida VARCHAR(20) NOT NULL,
    stock_actual NUMERIC(10, 3) NOT NULL DEFAULT 0.000 CHECK (stock_actual >= 0),
    stock_minimo NUMERIC(10, 3) NOT NULL DEFAULT 0.000 CHECK (stock_minimo >= 0),
    precio_adicional NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (precio_adicional >= 0),
    ubicacion VARCHAR(100),
    -- Regla de negocio: la unidad de medida es de dominio cerrado.
    CONSTRAINT chk_ingrediente_unidad
        CHECK (unidad_medida IN ('g', 'ml', 'unidad'))
);

CREATE TABLE Receta (
    id_receta SERIAL PRIMARY KEY,
    id_plato INT NOT NULL
        REFERENCES Plato(id_plato) ON DELETE RESTRICT,
    id_ingrediente INT NOT NULL
        REFERENCES Ingrediente(id_ingrediente) ON DELETE RESTRICT,
    cantidad_cruda_requerida NUMERIC(10, 3) NOT NULL CHECK (cantidad_cruda_requerida > 0),
    CONSTRAINT uq_receta_plato_ingrediente UNIQUE (id_plato, id_ingrediente)
);

-- ==========================================
-- 5. PEDIDOS Y DETALLE DE CONSUMO
-- ==========================================
CREATE TABLE Pedido (
    id_pedido SERIAL PRIMARY KEY,
    fecha_creacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cedula_empleado VARCHAR(20) NOT NULL
        REFERENCES Empleado(cedula) ON DELETE RESTRICT,
    id_mesa INT NOT NULL
        REFERENCES Mesa(id_mesa) ON DELETE RESTRICT,
    cedula_cliente VARCHAR(20) NOT NULL
        REFERENCES Cliente(cedula_cliente) ON DELETE RESTRICT,
    id_estado_pedido INT NOT NULL
        REFERENCES EstadoPedido(id_estado_pedido) ON DELETE RESTRICT
);

CREATE TABLE DetallePedido (
    id_detalle SERIAL PRIMARY KEY,
    id_pedido INT NOT NULL
        REFERENCES Pedido(id_pedido) ON DELETE CASCADE,
    id_plato INT NOT NULL
        REFERENCES Plato(id_plato) ON DELETE RESTRICT,
    cantidad_detallepedido INT NOT NULL DEFAULT 1 CHECK (cantidad_detallepedido > 0),
    -- Precio cobrado en el momento de la venta (foto historica: el precio_base
    -- del plato puede cambiar despues sin alterar ventas pasadas).
    precio_unitario NUMERIC(10, 2) NOT NULL CHECK (precio_unitario >= 0),
    observaciones TEXT
);

CREATE TABLE PersonalizacionDetalle (
    id_personalizacion SERIAL PRIMARY KEY,
    id_detalle INT NOT NULL
        REFERENCES DetallePedido(id_detalle) ON DELETE CASCADE,
    id_ingrediente INT NOT NULL
        REFERENCES Ingrediente(id_ingrediente) ON DELETE RESTRICT,
    tipo_accion VARCHAR(20) NOT NULL CHECK (tipo_accion IN ('AGREGAR', 'QUITAR')),
    cantidad_adicional NUMERIC(10, 3) DEFAULT 1.000,
    -- Foto del recargo cobrado por esta personalizacion (0 si es QUITAR). Se copia de
    -- Ingrediente.precio_adicional al vender; si ese precio cambia, la venta no cambia.
    precio_ajuste NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (precio_ajuste >= 0),
    CONSTRAINT chk_personalizacion_reglas CHECK (
        (tipo_accion = 'AGREGAR' AND cantidad_adicional > 0) OR
        (tipo_accion = 'QUITAR' AND (cantidad_adicional IS NULL OR cantidad_adicional = 0))
    )
);

-- ==========================================
-- 6. INVENTARIO, FACTURA Y NOVEDADES
-- ==========================================
CREATE TABLE MovimientoInventario (
    id_movimiento SERIAL PRIMARY KEY,
    id_ingrediente INT NOT NULL
        REFERENCES Ingrediente(id_ingrediente) ON DELETE RESTRICT,
    id_detalle INT
        REFERENCES DetallePedido(id_detalle) ON DELETE SET NULL,
    tipo_movimiento VARCHAR(50) NOT NULL,
    cantidad_movimiento NUMERIC(10, 3) NOT NULL,
    fecha_hora_movimiento TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- Regla de negocio: una venta nunca suma stock y una compra nunca lo resta.
    CONSTRAINT chk_movimiento_signo CHECK (
        (tipo_movimiento = 'SALIDA_VENTA'   AND cantidad_movimiento < 0) OR
        (tipo_movimiento = 'ENTRADA_COMPRA' AND cantidad_movimiento > 0)
    )
);

CREATE TABLE Factura (
    numero_factura VARCHAR(50) PRIMARY KEY,
    fecha_emision TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- Foto de lo cobrado al emitir la factura (un pedido puede tener n facturas).
    monto_total NUMERIC(10, 2) NOT NULL CHECK (monto_total >= 0),
    metodo_pago VARCHAR(50) NOT NULL,
    id_pedido INT NOT NULL
        REFERENCES Pedido(id_pedido) ON DELETE RESTRICT
);

CREATE TABLE Novedad (
    id_novedad SERIAL PRIMARY KEY,
    fecha_hora_novedad TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    descripcion_novedad TEXT NOT NULL,
    id_pedido INT NOT NULL
        REFERENCES Pedido(id_pedido) ON DELETE CASCADE,
    id_estado_pedido INT NOT NULL
        REFERENCES EstadoPedido(id_estado_pedido) ON DELETE RESTRICT
);

-- ==========================================
-- 7. INDICES
-- ==========================================
CREATE INDEX idx_plato_menu ON Plato(id_menu);
CREATE INDEX idx_pedido_cliente ON Pedido(cedula_cliente);
CREATE INDEX idx_pedido_mesa ON Pedido(id_mesa);
CREATE INDEX idx_pedido_empleado ON Pedido(cedula_empleado);
CREATE INDEX idx_detalle_pedido ON DetallePedido(id_pedido);
CREATE INDEX idx_personalizacion_detalle ON PersonalizacionDetalle(id_detalle);
CREATE INDEX idx_movimiento_ingrediente ON MovimientoInventario(id_ingrediente);
CREATE INDEX idx_movimiento_detalle ON MovimientoInventario(id_detalle);
CREATE INDEX idx_reserva_fecha ON Reserva(fecha_hora_inicio);

# Sistema de Gestion de Restaurante · Aplicacion Web (Equipo 5)

Aplicacion web desarrollada en **Python + Flask + ODBC (`pyodbc`)** conectada a **PostgreSQL** (Neon o local), con SQL escrito a mano (sin ORM) y capa de datos separada.

---

## 1. Requisitos previos

1. **Python 3.10 o superior**.
2. **Controlador ODBC de PostgreSQL (`psqlODBC` 64-bit)**:
   - En Windows debe aparecer instalado el driver `PostgreSQL Unicode(x64)` (se instala desde el Stack Builder de PostgreSQL o desde https://www.postgresql.org/ftp/odbc/releases/).
3. **Base de datos PostgreSQL (Neon o local)** con los scripts de `base_equipo5.zip` ejecutados en orden:
   1. `esquema_equipo5.sql`
   2. `poblar_equipo5.sql`
   3. `vistas_permisos_equipo5.sql`
   4. *(Opcional verificacion)* `consultas_equipo5.sql` y `pruebas_equipo5.sql`
4. **Asignar contrasenas a los dos usuarios fijos de la aplicacion** (a mano en `psql` o la consola SQL de Neon; nunca se guardan en los scripts):
   ```sql
   ALTER ROLE app_consulta  PASSWORD 'su_clave_segura_consulta';
   ALTER ROLE app_operacion PASSWORD 'su_clave_segura_operacion';
   ```

---

## 2. Configuracion externa (sin contrasenas en el codigo)

1. Entre a la carpeta `Restaurante/`.
2. Copie `.env.example` como `.env`:
   ```powershell
   Copy-Item .env.example .env
   ```
3. Edite `.env` con los datos reales de su servidor PostgreSQL (Neon o local) y las contrasenas que asigno en el paso anterior:
   - Para **Neon**: use el host de su proyecto (`ep-....neon.tech`), `DB_NAME=neondb` y `DB_SSLMODE=require`.
   - Para **PostgreSQL local**: use `DB_HOST=localhost`, el nombre de su base local y `DB_SSLMODE=prefer`.

> **Importante:** el archivo `.env` esta excluido en `.gitignore` y nunca debe incluirse en el `.zip` de entrega.

---

## 3. Instalacion de dependencias y ejecucion

Desde la carpeta `Restaurante/`:

### Opcion A — En CMD (Simbolo del sistema)
```bat
python -m venv .venv
.venv\Scripts\activate.bat
python -m pip install -r requirements.txt
python app.py
```

### Opcion B — En PowerShell
```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python app.py
```

*(Si no desea crear un entorno virtual, puede instalar las dependencias directamente con `python -m pip install -r requirements.txt` y ejecutar `python app.py`.)*

Luego abra en su navegador:

> **http://127.0.0.1:5000**

---

## 4. Ejecutar la demostracion de Inyeccion SQL (Requisito 10)

La demostracion vive en un script de prueba **aparte** (fuera de la aplicacion web):

```powershell
python pruebas/demo_inyeccion_sql.py
```

El script ejecuta la misma busqueda sobre `v_plato_publico` con la entrada `' OR '1'='1` primero de forma concatenada (vulnerable, devuelve todas las filas) y luego con sentencia preparada `?` (segura, devuelve 0 filas).

---

## 5. Estructura de capas

- `app.py` y `templates/`: servidor web HTTP y vistas HTML (sin SQL).
- `config/conexion.py`: lectura de `.env`, conexion ODBC (`pyodbc`), cambio de usuario por rol (`app_consulta` / `app_operacion`), cierre garantizado de cursores/conexiones y manejo de base caida/dormida.
- `dao/`: capa de datos con SQL escrito a mano y 100 % sentencias preparadas (`?`):
  - `errores_pg.py`: traduccion de excepciones (`23505` UNIQUE, `23514` CHECK, `23503` FK, `42501` permisos).
  - `busqueda_dao.py`: Req 2 (`WHERE ILIKE ?` + `ORDER BY` con desempate).
  - `reportes_dao.py`: Req 3 (`GROUP BY` + `HAVING` + tasas con denominador explicito).
  - `detalle_dao.py`: Req 4 (JOIN de 4 y 6 tablas + `LEFT JOIN` con ceros visibles).
  - `alertas_dao.py`: Req 5 (`NOT EXISTS` + subconsulta correlacionada).
  - `vistas_dao.py`: Req 6 y 7 (lectura sobre `v_pedido_publico` y `v_cliente_publico` + pruebas reales de permisos).
  - `plato_dao.py`: Req 8 (`INSERT`, `UPDATE`, `DELETE` con conteo de filas afectadas).
  - `reserva_dao.py`: Req 9 y Regla B.2 (validacion de capacidad + no solapamiento, transaccion `Reserva` + `Mesa`, `COMMIT` / `ROLLBACK` y fallo forzado a la mitad).
- `pruebas/demo_inyeccion_sql.py`: Req 10 (archivo aparte de demostracion de inyeccion SQL).

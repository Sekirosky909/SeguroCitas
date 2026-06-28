# Seguro Médico Integral conectado a SQL Server

Este proyecto usa el HTML entregado por el usuario y lo conecta a SQL Server por medio de FastAPI.
## Notas importantes
para poder usar este proyecto debes tener instalado `Python` y la extensión de visual studio code `live preview`

Si deseas puedes descargarlo desde `Powershell`, para esto, instalaras python desde este simbolo de sistema.
```text
Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.14.0/python-3.14.0-amd64.exe" -OutFile "$env:USERPROFILE\Downloads\python-3.14.0-amd64.exe"
```

Al descargarlo puedes abrirlo con el siguiente comando.
```text
Start-Process "$env:USERPROFILE\Downloads\python-3.14.0-amd64.exe"
```

Al instalarlo, recuerda marcar la casilla "Add Python to PATH" antes de hacer clic en Install Now.

Para probarlo usa el comando 

```text
python --version
```
## Estructura

```text
index.html
styles.css
app.js
api.py
requirements.txt
database.sql
```

## 1. Ejecutar la base de datos

En SSMS, conéctate a:

```text
JOHAM\SQLEXPRESS
```

Marca **Trust server certificate / Certificado de servidor de confianza** y ejecuta:

```text
database.sql
```

Esto crea la base:

```text
SeguroMedicoDB
```

## 2. Instalar dependencias del backend

En PowerShell, dentro de esta carpeta:

```powershell
py -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
```

## 3. Ejecutar FastAPI

```powershell
uvicorn api:app --reload
```

Prueba:

```text
http://127.0.0.1:8000/docs
http://127.0.0.1:8000/api/catalogos
```

## 4. Ejecutar la página web

Abre otra terminal en la misma carpeta:

```powershell
python -m http.server 5500
```

Luego entra a:

```text
http://127.0.0.1:5500
```

## Login admin

```text
Usuario: admin
Contraseña: Seguro123
```

## Nota

La página no se conecta directo a SQL Server. El flujo correcto es:

```text
HTML/CSS/JS -> FastAPI -> SQL Server
```

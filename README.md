# TalentFlow

Fundacion de infraestructura de TalentFlow: React + Vite + TypeScript, PostgreSQL y n8n mediante Docker Compose.

## Requisitos

- Docker Desktop o Docker Engine con Docker Compose v2.
- Puertos libres para PostgreSQL, n8n y frontend, o puertos alternativos configurados en `.env`.

## Configuracion

Desde PowerShell, entre a la carpeta del proyecto y cree el archivo local de variables:

```powershell
cd talentflow
Copy-Item .env.example .env
```

Edite `.env`, reemplace `POSTGRES_PASSWORD` y `N8N_ENCRYPTION_KEY`, y cambie los puertos si existe algun conflicto. `.env` esta ignorado por Git y no debe versionarse.

Cuando se cambien `N8N_HOST_PORT` o `FRONTEND_HOST_PORT`, actualice tambien las URLs locales correspondientes en `.env`.

## Ejecucion

Todos los comandos son compatibles con PowerShell:

```powershell
docker compose up -d
docker compose ps
docker compose logs -f
docker compose down
```

Para eliminar tambien los datos persistentes, solo cuando sea intencional:

```powershell
docker compose down -v
```

## URLs locales

Con los valores predeterminados de `.env.example`:

- Frontend: `http://localhost:5173`
- n8n: `http://localhost:5679`
- PostgreSQL desde el host: `localhost:5433`

Si modifica `FRONTEND_HOST_PORT`, `N8N_HOST_PORT` o `POSTGRES_HOST_PORT`, sustituya el puerto en la URL o conexion del host. Entre contenedores no se usa `localhost`: n8n se conecta a `postgres:5433`, y cualquier contenedor que necesite n8n debe usar `http://n8n:5679`.

## Verificacion

Compruebe que los tres servicios muestran estado `healthy`:

```powershell
docker compose ps
```

Verifique que n8n resuelve PostgreSQL por el nombre interno del servicio:

```powershell
docker compose exec n8n node -e "require('dns').lookup('postgres', (error, address) => { if (error) throw error; console.log('postgres -> ' + address) })"
```

Verifique que el puerto de PostgreSQL es alcanzable desde n8n:

```powershell
docker compose exec n8n node -e "const net=require('net'); const socket=net.connect(5433,'postgres',()=>{console.log('postgres:5433 accesible');socket.end()}); socket.on('error',error=>{console.error(error);process.exit(1)})"
```

El frontend incluye placeholders navegables para `/`, `/vacantes` y `/admin`. Este modulo no incluye tablas de negocio, workflows funcionales ni integraciones externas.

## Panel administrativo

El Modulo 3 se encuentra en `http://localhost:5174/admin` con los puertos locales actuales. La preparacion de los workflows, endpoints y pruebas se documenta en `docs/module-3-admin.md`.

# Agents.md — docker-ultimate-manager

Guía para agentes de IA que trabajen sobre este repositorio.

---

## Descripción del proyecto

`docker-ultimate-manager.sh` es un gestor interactivo de contenedores Docker basado en TUI (terminal UI). Está diseñado para entornos **WSL2 en Windows** y organiza los contenedores en **proyectos** (grupos de contenedores que comparten prefijo de nombre).

El script hermano `docker-manager.sh` es una versión anterior, más simple. No modificar salvo que se pida explícitamente.

---

## Entorno de ejecución

- Shell: `bash` (no es compatible con `sh` ni `zsh`)
- Plataforma objetivo: WSL2 (Linux 6.6.x + Windows)
- Requiere: Docker con daemon activo
- Notificaciones: opcionales vía `powershell.exe` (solo disponible en WSL2)
- `set -uo pipefail` activo — las variables no declaradas lanzan error

---

## Archivos persistentes

| Ruta | Propósito |
|------|-----------|
| `~/.docker-manager.conf` | Configuración (`NOTIFICATIONS`, `BACKUP_PATH`) |
| `~/.docker-favorites` | Lista de proyectos favoritos, uno por línea, `#` como comentario |
| `~/.docker-history` | Log de acciones con timestamp |
| `~/docker-backups/<proyecto>/` | Destino de backups de `docker inspect` |

La config **no se hace source** — se parsea con `grep`/`cut` para evitar ejecución de código arbitrario.

---

## Arquitectura de funciones

### Núcleo / utilidades

| Función | Propósito |
|---------|-----------|
| `init_config` | Crea ficheros si no existen, parsea config, valida Docker |
| `log_action ACTION PROJECT` | Añade entrada a `~/.docker-history` |
| `notify TITLE TEXT` | Notificación Windows vía PowerShell (no bloquea si falla) |
| `escape_ps_string STR` | Escapa comillas simples para PowerShell |
| `extract_project_name NAME` | Extrae el prefijo antes de `_` o `-` |
| `get_projects` | Lista proyectos únicos detectados en `docker ps -a` |
| `get_project_pattern PROJECT` | Devuelve regex `^project[_-]` o `^project$` para filtros Docker |
| `get_restart_policy CONTAINER` | Devuelve la política de reinicio del contenedor |

### Gestión de proyectos

| Función | Acción |
|---------|--------|
| `start_project PROJECT` | Inicia contenedores `exited` del proyecto |
| `stop_project PROJECT` | Detiene contenedores activos del proyecto |
| `restart_project PROJECT` | Llama a stop + start (no loguea por separado) |
| `remove_project PROJECT` | Elimina con confirmación explícita (`ELIMINAR`) |
| `logs_project PROJECT` | Muestra últimas 30 líneas de cada contenedor |
| `status_project PROJECT` | Tabla de nombres/estado/puertos |
| `show_project_ports PROJECT` | Muestra puertos y URLs `http://localhost:PORT` |
| `change_restart_policy PROJECT` | Cambia política a `no/unless-stopped/always/on-failure` |
| `backup_project PROJECT` | Guarda `docker inspect` JSON en `BACKUP_PATH` (solo metadata) |
| `open_in_browser PROJECT` | Extrae el primer puerto expuesto y lo abre en el navegador |
| `compose_project PROJECT` | Busca `docker-compose.yml` y ofrece up/down/restart/logs |

### Menús y vistas

| Función | Descripción |
|---------|-------------|
| `manage_projects` | Listado interactivo de proyectos con submenú de acciones |
| `show_project_actions PROJECT` | Renderiza el menú de acciones para un proyecto |
| `show_favorites` | Gestión de favoritos (listar, añadir, remover, iniciar) |
| `add_favorite` / `remove_favorite` | Editan `~/.docker-favorites` |
| `search_containers` | Búsqueda de cadena literal en `docker ps -a` |
| `quick_actions` | Operaciones masivas (detener todos, limpiar, etc.) |
| `global_status` | Resumen global + `docker system df` |
| `show_all_ports` | Mapa de puertos de todos los contenedores activos |
| `show_history` | Últimas 30 entradas del historial |
| `stop_all_forever` | Detiene todo y establece `restart=no` en todos los contenedores |
| `show_main_menu` | Renderiza el menú principal (solo imprime, no lee input) |

---

## Convenciones de código

- **Idioma UI:** español. Los mensajes al usuario, prompts y menús van en español.
- **Bucles de lectura:** siempre `while IFS= read -r var; do` — nunca `while read var`.
- **Variables de IDs Docker:** capturar antes de usar; comprobar si están vacías antes de pasarlas a `docker stop/start/rm`. Nunca `docker stop $(docker ps -q)` directamente.
- **Subshells en filtros:** usar `--filter "name=PATTERN"` de Docker en lugar de `grep` post-proceso cuando sea posible.
- **Patrones de proyecto:** siempre obtenidos con `get_project_pattern` — no construir el regex a mano.
- **Notificaciones:** siempre en `notify`, nunca llamar `powershell.exe` directamente desde otra función.
- **Sed con input de usuario:** prohibido. Usar `grep -Fxv` u otras alternativas que no interpreten el input como expresión.

---

## Flujo de inicio

```
init_config
  ├── Crea ficheros faltantes
  ├── Parsea ~/.docker-manager.conf
  └── Valida: docker disponible + daemon activo → exit 1 si falla

Bucle principal
  show_main_menu → read opt → dispatch a función correspondiente
```

---

## Qué NO hacer

- No usar `source` ni `.` sobre ficheros de configuración del usuario.
- No añadir `set -e` — el script gestiona errores manualmente para evitar salidas inesperadas en TUI.
- No reemplazar `docker-compose` directamente: `compose_project` detecta si usar `docker-compose` (legacy) o `docker compose` (plugin moderno).
- No escribir en `~/.docker-history` directamente — usar `log_action`.
- No llamar `stop_project`/`start_project` dentro de una función y luego loguear `RESTART` por separado: genera entradas duplicadas.

---

## Cómo probar cambios

```bash
# Verificar sintaxis antes de ejecutar
bash -n docker-ultimate-manager.sh

# Ejecutar en terminal (requiere Docker activo)
bash docker-ultimate-manager.sh

# Comprobar que no haya variables no declaradas en flujos frecuentes
bash -uo pipefail docker-ultimate-manager.sh
```

No hay suite de tests automatizados. Las pruebas son manuales a través del TUI.

---

## Expansión futura conocida

- `backup_project` solo guarda `docker inspect` (metadata). Una expansión real requeriría backup de volúmenes con `docker run --volumes-from`.
- `search_containers` busca solo en contenedores activos/parados. No busca en imágenes ni redes.
- `compose_project` busca el fichero solo en tres rutas hardcodeadas. Podría extenderse con detección automática.

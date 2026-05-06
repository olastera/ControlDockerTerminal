# Docker Project Manager

Gestor de proyectos Docker con interfaz interactiva en terminal. Administra contenedores agrupados por proyecto con menús coloridos y acciones rápidas.

## Scripts disponibles

### 1. `docker-manager.sh` - Gestor Básico

Versión ligera para gestión estándar de proyectos Docker.

**Funcionalidades:**
- 📦 **Gestión por proyectos** - Detecta proyectos automáticamente (prefijos con `_` o `-`)
- 🟢 **Iniciar/Detener/Reiniciar** contenedores por proyecto
- 🗑️ **Eliminar** proyectos completos (con confirmación)
- 📋 **Ver logs** (últimas 30 líneas)
- 📊 **Estado detallado** (contenedores, imágenes, uso de recursos)
- 🔌 **Ver puertos** mapeados por proyecto y global
- 🔧 **Política de reinicio** - Cambiar `no/always/unless-stopped/on-failure`
- 🐳 **Docker Compose** - Ejecutar comandos desde ubicaciones comunes
- ⚡ **Acciones rápidas** - Detener/iniciar todos, limpiar sistema
- 🛑🔒 **Detener todo + desactivar auto-inicio** - Previene arranques automáticos

**Menú principal:**
```
1) 🎯 Gestionar por PROYECTOS
2) 🗺️  Ver mapa de puertos (todos)
3) ⚡ Acciones rápidas
4) 📊 Ver estado global
5) 🐳 Ver solo contenedores activos
6) 🔴 Ver solo contenedores detenidos
7) 🛑🔒 DETENER TODO y desactivar auto-inicio
0) ❌ Salir
```

---

### 2. `docker-ultimate-manager.sh` - Gestor Avanzado

Versión completa con características adicionales para productividad avanzada.

**Incluye todo lo de la versión básica, más:**

- ⭐ **Favoritos** - Guarda proyectos frecuentes para acceso rápido
- 📜 **Historial** - Registro de acciones realizadas (`~/.docker-history`)
- 🔔 **Notificaciones** - Alertas de Windows al completar acciones (vía PowerShell)
- 💾 **Backup** - Exporta configuración JSON de contenedores con timestamp
- 🔍 **Búsqueda** - Filtra contenedores por nombre o imagen
- 🌐 **Abrir en navegador** - Detecta puertos expuestos y abre la URL
- ⚙️ **Configuración persistente** (`~/.docker-manager.conf`)
  - `NOTIFICATIONS=true/false`
  - `BACKUP_PATH=$HOME/docker-backups`
- 🔒 **Seguridad mejorada** - Sin `source` de archivos externos, escape de inputs

**Menú principal:**
```
1) 🎯 Gestionar por PROYECTOS
2) 🗺️  Ver mapa de puertos (todos)
3) ⚡ Acciones rápidas
4) 📊 Ver estado global
5) ⭐ Gestionar favoritos
6) 🔍 Búsqueda
7) 🛑🔒 DETENER TODO y desactivar auto-inicio
8) 📜 Ver historial
0) ❌ Salir
```

---

## Instalación

```bash
# Dar permisos de ejecución
chmod +x docker-manager.sh
chmod +x docker-ultimate-manager.sh

# Ejecutar
./docker-manager.sh
# o
./docker-ultimate-manager.sh
```

## Requisitos

- Docker instalado y en ejecución
- Bash 4+
- `docker compose` (plugin moderno) o `docker-compose` (legacy) — opcional, para la función de compose

## Cómo detecta los proyectos

El script extrae el nombre del proyecto usando el primer segmento del nombre del contenedor:
- `miapp_web` → proyecto: `miapp`
- `miapp-db` → proyecto: `miapp`
- `miapp` → proyecto: `miapp`

## Archivos generados

| Archivo | Descripción |
|---------|-------------|
| `~/.docker-favorites` | Lista de proyectos favoritos |
| `~/.docker-history` | Registro de acciones (últimas 30 entradas) |
| `~/.docker-manager.conf` | Configuración (notificaciones, backup path) |

## Seguridad

La versión `docker-ultimate-manager.sh` incluye las siguientes mejoras de seguridad:
- ✅ Validación de Docker instalado y daemon activo al arrancar
- ✅ Configuración leída sin `source` (previene ejecución de código arbitrario)
- ✅ Inputs de usuario nunca interpolados en expresiones `sed` — se usa `grep -Fxv` (cadena literal)
- ✅ Búsqueda con `grep -iF` (cadena literal, no regex) para evitar inyección de patrones
- ✅ Escape de caracteres especiales en nombres de proyecto para filtros Docker
- ✅ Sanitizado de inputs en PowerShell (notificaciones)
- ✅ Manejo seguro de directorios con `pushd`/`popd`
- ✅ `set -uo pipefail` para detección de variables no declaradas y errores en pipes
- ✅ Comprobación de IDs vacíos antes de operaciones masivas (`docker stop/start/rm`)

## Créditos

Gestor de proyectos Docker desarrollado para simplificar la administración de múltiples contenedores desde la terminal.

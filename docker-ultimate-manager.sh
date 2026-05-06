#!/bin/bash
set -uo pipefail

# ============================================
# CONFIGURACIÓN DE COLORES
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m'

escape_ps_string() {
    echo "$1" | sed "s/'/''/g"
}

# Archivos de configuración
FAVORITES_FILE="$HOME/.docker-favorites"
HISTORY_FILE="$HOME/.docker-history"
CONFIG_FILE="$HOME/.docker-manager.conf"

# ============================================
# INICIALIZACIÓN
# ============================================
init_config() {
    if [ ! -f "$FAVORITES_FILE" ]; then
        cat > "$FAVORITES_FILE" << 'EOF'
# Proyectos favoritos - uno por línea
# Ejemplo: iespai
EOF
    fi
    if [ ! -f "$HISTORY_FILE" ]; then
        touch "$HISTORY_FILE"
    fi
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << 'EOF'
NOTIFICATIONS=true
BACKUP_PATH=$HOME/docker-backups
EOF
    fi
    # Safe config parsing instead of source
    NOTIFICATIONS=$(grep -E '^NOTIFICATIONS=' "$CONFIG_FILE" | cut -d= -f2 | tr -d '"' | tr -d "'")
    BACKUP_PATH=$(grep -E '^BACKUP_PATH=' "$CONFIG_FILE" | cut -d= -f2- | tr -d '"' | tr -d "'")
    # Expand $HOME in BACKUP_PATH if present
    if [[ "$BACKUP_PATH" == *"\$HOME"* ]]; then
        BACKUP_PATH="${BACKUP_PATH/\$HOME/$HOME}"
    fi
    # Set defaults if empty
    NOTIFICATIONS=${NOTIFICATIONS:-true}
    BACKUP_PATH=${BACKUP_PATH:-$HOME/docker-backups}
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}❌ Docker no encontrado. Instala Docker primero.${NC}"
        exit 1
    fi
    if ! docker info &>/dev/null 2>&1; then
        echo -e "${RED}❌ Docker daemon no está corriendo.${NC}"
        exit 1
    fi
}

log_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1: $2" >> "$HISTORY_FILE"
}

notify() {
    if [ "$NOTIFICATIONS" = true ] && command -v powershell.exe &>/dev/null; then
        local title=$(escape_ps_string "$1")
        local text=$(escape_ps_string "$2")
        powershell.exe -Command "& {Add-Type -AssemblyName System.Windows.Forms; \`\$notification = New-Object System.Windows.Forms.NotifyIcon; \`\$notification.Icon = [System.Drawing.SystemIcons]::Information; \`\$notification.BalloonTipTitle = '$title'; \`\$notification.BalloonTipText = '$text'; \`\$notification.Visible = \`\$true; \`\$notification.ShowBalloonTip(3000)}" 2>/dev/null
    fi
}

extract_project_name() {
    local name=$1
    if [[ "$name" == *"_"* ]] || [[ "$name" == *"-"* ]]; then
        echo "$name" | sed -E 's/^([^_-]+)[_-].*/\1/'
    else
        echo "$name"
    fi
}

get_projects() {
    docker ps -a --format "{{.Names}}" 2>/dev/null | while IFS= read -r name; do
        extract_project_name "$name"
    done | sort -u
}

get_project_pattern() {
    local project=$1
    local escaped_project=$(echo "$project" | sed 's/[][\.*^$(){}?+|/]/\\&/g')
    local has_prefixed=$(docker ps -a --format "{{.Names}}" 2>/dev/null | grep -E "^${escaped_project}[_-]" | head -1)
    if [ -n "$has_prefixed" ]; then
        if [[ "$has_prefixed" == *"_"* ]]; then
            echo "^${escaped_project}_"
        else
            echo "^${escaped_project}-"
        fi
    else
        echo "^${escaped_project}$"
    fi
}

get_restart_policy() {
    docker inspect --format='{{.HostConfig.RestartPolicy.Name}}' "$1" 2>/dev/null
}

# ============================================
# FUNCIONES PRINCIPALES DEL PROYECTO
# ============================================

start_project() {
    local project=$1
    local pattern=$(get_project_pattern "$project")
    local containers=$(docker ps -a --filter "name=${pattern}" --filter "status=exited" --format "{{.Names}}" 2>/dev/null)
    if [ -z "$containers" ]; then
        echo -e "${GREEN}✅ Todos los contenedores ya están activos${NC}"
    else
        echo -e "${YELLOW}⏳ Iniciando proyecto $project...${NC}"
        echo "$containers" | while IFS= read -r c; do [ -n "$c" ] && docker start "$c" >/dev/null 2>&1 && echo "  🚀 $c"; done
        echo -e "${GREEN}✅ Proyecto $project iniciado${NC}"
        log_action "START" "$project"
        notify "Docker Manager" "Proyecto $project iniciado"
    fi
}

stop_project() {
    local project=$1
    local pattern=$(get_project_pattern "$project")
    local containers=$(docker ps --filter "name=${pattern}" --format "{{.Names}}" 2>/dev/null)
    if [ -z "$containers" ]; then
        echo -e "${GREEN}✅ Proyecto ya está detenido${NC}"
    else
        echo -e "${YELLOW}⏳ Deteniendo proyecto $project...${NC}"
        echo "$containers" | while IFS= read -r c; do [ -n "$c" ] && docker stop "$c" >/dev/null 2>&1 && echo "  🛑 $c"; done
        echo -e "${GREEN}✅ Proyecto $project detenido${NC}"
        log_action "STOP" "$project"
        notify "Docker Manager" "Proyecto $project detenido"
    fi
}

restart_project() {
    echo -e "${YELLOW}⏳ Reiniciando $1...${NC}"
    stop_project "$1"
    sleep 1
    start_project "$1"
}

remove_project() {
    local pattern=$(get_project_pattern "$1")
    echo -e "${RED}⚠️  ¿Eliminar proyecto $1?${NC}"
    docker ps -a --filter "name=${pattern}" --format "  - {{.Names}}" 2>/dev/null
    read -p "Escribe 'ELIMINAR' para confirmar: " confirm
    if [ "$confirm" = "ELIMINAR" ]; then
        local ids=$(docker ps -a --filter "name=${pattern}" -q 2>/dev/null)
        if [ -n "$ids" ]; then
            echo "$ids" | xargs docker rm -f 2>/dev/null
        fi
        echo -e "${GREEN}✅ Proyecto $1 eliminado${NC}"
        log_action "REMOVE" "$1"
    fi
}

logs_project() {
    local pattern=$(get_project_pattern "$1")
    clear
    echo -e "${BLUE}═══════════════ LOGS DE $1 ═══════════════${NC}"
    docker ps -a --filter "name=${pattern}" --format "{{.Names}}" 2>/dev/null | while IFS= read -r c; do
        [ -n "$c" ] && echo -e "\n${CYAN}━━━ $c ━━━${NC}" && docker logs --tail=30 "$c" 2>/dev/null
    done
    read -p "Presiona Enter..."
}

status_project() {
    local pattern=$(get_project_pattern "$1")
    clear
    echo -e "${BLUE}═══════════════ ESTADO DE $1 ═══════════════${NC}"
    docker ps -a --filter "name=${pattern}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null
    echo ""
    read -p "Presiona Enter..."
}

show_project_ports() {
    local pattern=$(get_project_pattern "$1")
    clear
    echo -e "${BLUE}═══════════════ PUERTOS DE $1 ═══════════════${NC}"
    docker ps --filter "name=${pattern}" --format "{{.Names}}" 2>/dev/null | while IFS= read -r c; do
        if [ -n "$c" ]; then
            echo -e "\n${GREEN}📦 $c${NC}"
            docker port "$c" 2>/dev/null | while IFS= read -r p; do
                url=$(echo "$p" | sed 's/0.0.0.0:/http:\/\/localhost:/' | sed 's/->.*//')
                echo "  🔗 $p"
                [[ "$url" == http* ]] && echo "     📎 ${GREEN}$url${NC}"
            done
        fi
    done
    read -p "Presiona Enter..."
}

change_restart_policy() {
    local pattern=$(get_project_pattern "$1")
    echo ""
    echo -e "${YELLOW}Políticas disponibles:${NC}"
    echo "  1) no             - No reiniciar automáticamente (RECOMENDADO)"
    echo "  2) unless-stopped - Reiniciar solo si no fue detenido manualmente"
    echo "  3) always         - Siempre reiniciar (EVITAR)"
    echo "  4) on-failure     - Reiniciar solo si falla"
    read -p "Selecciona (1-4): " choice
    case $choice in
        1) new="no" ;;
        2) new="unless-stopped" ;;
        3) new="always" ;;
        4) new="on-failure" ;;
        *) return ;;
    esac
    docker ps -a --filter "name=${pattern}" --format "{{.Names}}" 2>/dev/null | while IFS= read -r c; do
        [ -n "$c" ] && docker update --restart="$new" "$c" >/dev/null 2>&1 && echo "  ✓ $c → $new"
    done
    echo -e "${GREEN}✅ Política actualizada${NC}"
    log_action "CHANGE_POLICY" "$1 ($new)"
}

backup_project() {
    local pattern=$(get_project_pattern "$1")
    local backup_path="${BACKUP_PATH:-$HOME/docker-backups}/$1"
    mkdir -p "$backup_path"
    local ts=$(date '+%Y%m%d_%H%M%S')
    echo -e "${YELLOW}💾 Backup de $1...${NC}"
    docker ps -a --filter "name=${pattern}" --format "{{.Names}}" 2>/dev/null | while IFS= read -r c; do
        [ -n "$c" ] && docker inspect "$c" > "$backup_path/${c}_$ts.json" && echo "  ✓ $c"
    done
    echo -e "${GREEN}✅ Backup en: $backup_path${NC}"
    log_action "BACKUP" "$1"
}

open_in_browser() {
    local pattern=$(get_project_pattern "$1")
    local port=$(docker ps --filter "name=${pattern}" --format "{{.Ports}}" 2>/dev/null | grep -oP '0\.0\.0\.0:\K[0-9]+' | head -1)
    if [ -n "$port" ]; then
        local url="http://localhost:$port"
        echo -e "${GREEN}🌐 Abriendo $url...${NC}"
        local escaped_url=$(escape_ps_string "$url")
        powershell.exe -Command "Start-Process '$escaped_url'" 2>/dev/null || xdg-open "$url" 2>/dev/null || open "$url" 2>/dev/null
    else
        echo -e "${RED}No se encontró puerto expuesto${NC}"
    fi
}

compose_project() {
    local project=$1
    local compose_cmd
    if command -v docker-compose &>/dev/null; then
        compose_cmd="docker-compose"
    else
        compose_cmd="docker compose"
    fi
    local paths=("$HOME/proyectos/$project" "$HOME/$project" "$HOME/docker/$project")
    for path in "${paths[@]}"; do
        if [ -f "$path/docker-compose.yml" ]; then
            pushd "$path" > /dev/null || { echo -e "${RED}No se pudo acceder a $path${NC}"; return; }
            echo -e "${GREEN}✅ docker-compose.yml encontrado en $path${NC}"
            echo "  1) up -d   2) down   3) restart   4) logs   0) Salir"
            read -p "Opción: " opt
            case $opt in
                1) $compose_cmd up -d ;;
                2) $compose_cmd down ;;
                3) $compose_cmd restart ;;
                4) $compose_cmd logs --tail=50 ;;
            esac
            log_action "COMPOSE" "$project"
            read -p "Presiona Enter..."
            popd > /dev/null || true
            return
        fi
    done
    echo -e "${RED}❌ No se encontró docker-compose.yml${NC}"
}

# ============================================
# MENÚ DE ACCIONES DEL PROYECTO
# ============================================

show_project_actions() {
    local project=$1
    local pattern=$(get_project_pattern "$project")
    local total=$(docker ps -a --filter "name=${pattern}" -q 2>/dev/null | wc -l)
    local running=$(docker ps --filter "name=${pattern}" -q 2>/dev/null | wc -l)
    
    clear
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}        🎯 GESTIONANDO PROYECTO: ${MAGENTA}$project${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e " Estado: $running/$total contenedores activos"
    echo ""
    echo -e " ${YELLOW}1)${NC} 🟢 INICIAR todos"
    echo -e " ${YELLOW}2)${NC} 🛑 DETENER todos"
    echo -e " ${YELLOW}3)${NC} 🔄 REINICIAR todos"
    echo -e " ${YELLOW}4)${NC} 🗑️  ELIMINAR todos"
    echo -e " ${YELLOW}5)${NC} 📋 Ver logs"
    echo -e " ${YELLOW}6)${NC} 📊 Ver estado"
    echo -e " ${YELLOW}7)${NC} 🔌 Ver puertos"
    echo -e " ${YELLOW}8)${NC} 🔧 Política de reinicio"
    echo -e " ${YELLOW}9)${NC} 💾 Backup"
    echo -e " ${YELLOW}10)${NC} 🌐 Abrir en navegador"
    echo -e " ${YELLOW}11)${NC} 🐳 Docker-compose"
    echo -e " ${YELLOW}0)${NC} Volver"
    echo ""
}

manage_projects() {
    while true; do
        clear
        echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}              📦 PROYECTOS DETECTADOS${NC}"
        echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
        echo ""
        
        local index=1
        local -a projects_list
        while IFS= read -r p; do
            if [ -n "$p" ]; then
                projects_list[$index]="$p"
                local pattern=$(get_project_pattern "$p")
                local total=$(docker ps -a --filter "name=${pattern}" -q 2>/dev/null | wc -l)
                local running=$(docker ps --filter "name=${pattern}" -q 2>/dev/null | wc -l)
                if [ $running -eq 0 ]; then
                    echo -e " ${YELLOW}$index)${NC} ${MAGENTA}$p${NC} - ${RED}● DETENIDO${NC} (0/$total)"
                elif [ $running -eq $total ]; then
                    echo -e " ${YELLOW}$index)${NC} ${MAGENTA}$p${NC} - ${GREEN}● ACTIVO${NC} ($running/$total)"
                else
                    echo -e " ${YELLOW}$index)${NC} ${MAGENTA}$p${NC} - ${CYAN}● PARCIAL${NC} ($running/$total)"
                fi
                ((index++))
            fi
        done < <(get_projects)
        
        echo ""
        echo -e " ${YELLOW}F)${NC} ⭐ Favoritos"
        echo -e " ${YELLOW}S)${NC} 🔍 Buscar"
        echo -e " ${YELLOW}0)${NC} Volver"
        echo ""
        read -p "Selecciona: " choice
        
        if [ "$choice" = "0" ]; then
            break
        elif [[ "$choice" =~ ^[Ff]$ ]]; then
            show_favorites
            continue
        elif [[ "$choice" =~ ^[Ss]$ ]]; then
            search_containers
            continue
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ -n "${projects_list[$choice]}" ]; then
            local project="${projects_list[$choice]}"
            while true; do
                show_project_actions "$project"
                read -p "➤ Acción: " action
                case $action in
                    1) start_project "$project"; break ;;
                    2) stop_project "$project"; break ;;
                    3) restart_project "$project"; break ;;
                    4) remove_project "$project"; break ;;
                    5) logs_project "$project"; break ;;
                    6) status_project "$project"; break ;;
                    7) show_project_ports "$project"; break ;;
                    8) change_restart_policy "$project"; break ;;
                    9) backup_project "$project"; break ;;
                    10) open_in_browser "$project"; break ;;
                    11) compose_project "$project"; break ;;
                    0) break ;;
                    *) echo -e "${RED}Opción inválida${NC}"; sleep 1 ;;
                esac
            done
        fi
    done
}

# ============================================
# FAVORITOS
# ============================================

show_favorites() {
    clear
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    ⭐ PROYECTOS FAVORITOS${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local favs=()
    while IFS= read -r line; do
        [[ "$line" =~ ^# ]] || [ -z "$line" ] || favs+=("$line")
    done < "$FAVORITES_FILE"
    
    if [ ${#favs[@]} -eq 0 ]; then
        echo -e "${YELLOW}⚠️  No hay favoritos${NC}"
        echo ""
        echo -e "Para añadir: ${YELLOW}A)${NC} Añadir proyecto"
        read -p "Opción: " opt
        [[ "$opt" =~ ^[Aa]$ ]] && add_favorite
    else
        for i in "${!favs[@]}"; do
            local pattern=$(get_project_pattern "${favs[$i]}")
            local running=$(docker ps --filter "name=${pattern}" -q 2>/dev/null | wc -l)
            local status="🔴"
            [ $running -gt 0 ] && status="🟢"
            echo -e " ${YELLOW}$((i+1))${NC}) $status ${MAGENTA}${favs[$i]}${NC}"
        done
        echo ""
        echo -e " ${YELLOW}A)${NC} Añadir    ${YELLOW}R)${NC} Remover    ${YELLOW}0)${NC} Volver"
        read -p "Selecciona: " opt
        
        if [[ "$opt" =~ ^[0-9]+$ ]] && [ "$opt" -le ${#favs[@]} ]; then
            start_project "${favs[$((opt-1))]}"
        elif [[ "$opt" =~ ^[Aa]$ ]]; then
            add_favorite
        elif [[ "$opt" =~ ^[Rr]$ ]]; then
            remove_favorite
        fi
    fi
}

add_favorite() {
    read -p "Nombre del proyecto: " project
    if grep -Fqx "$project" "$FAVORITES_FILE" 2>/dev/null; then
        echo -e "${YELLOW}Ya existe${NC}"
    else
        echo "$project" >> "$FAVORITES_FILE"
        echo -e "${GREEN}✅ Añadido${NC}"
    fi
}

remove_favorite() {
    read -p "Nombre del proyecto: " project
    grep -Fxv "$project" "$FAVORITES_FILE" > "${FAVORITES_FILE}.tmp" && mv "${FAVORITES_FILE}.tmp" "$FAVORITES_FILE"
    echo -e "${GREEN}✅ Eliminado${NC}"
}

# ============================================
# BÚSQUEDA
# ============================================

search_containers() {
    clear
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    🔍 BÚSQUEDA${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo ""
    read -p "Buscar: " term
    echo ""
    echo -e "${CYAN}Resultados:${NC}"
    docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null | grep -iF --color=always "$term" || echo "  No encontrado"
    read -p "Presiona Enter..."
}

# ============================================
# ACCIONES RÁPIDAS
# ============================================

quick_actions() {
    clear
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    ⚡ ACCIONES RÁPIDAS${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo " 1) 🛑 DETENER todos los contenedores"
    echo " 2) 🚀 INICIAR todos los contenedores detenidos"
    echo " 3) 🛑🔒 DETENER TODO y DESACTIVAR auto-inicio"
    echo " 4) 🗑️  Limpiar contenedores detenidos"
    echo " 5) 🧹 Limpiar todo (sistema)"
    echo " 0) Volver"
    echo ""
    read -p "Opción: " opt
    
    case $opt in
        1)
            read -p "¿Detener TODOS? (SI/no): " c
            if [[ "$c" = "SI" ]]; then
                ids=$(docker ps -q 2>/dev/null); [ -n "$ids" ] && docker stop $ids 2>/dev/null
                echo "✅ Detenidos"
            fi
            ;;
        2)
            ids=$(docker ps -a --filter "status=exited" -q 2>/dev/null)
            if [ -n "$ids" ]; then
                docker start $ids 2>/dev/null
                echo "✅ Iniciados"
            else
                echo "No hay contenedores detenidos"
            fi
            ;;
        3)
            read -p "Escribe 'CONFIRMAR': " c
            if [ "$c" = "CONFIRMAR" ]; then
                ids=$(docker ps -q 2>/dev/null); [ -n "$ids" ] && docker stop $ids 2>/dev/null
                docker ps -a -q | while IFS= read -r id; do
                    docker update --restart=no "$id" 2>/dev/null
                done
                echo -e "${GREEN}✅ Todo detenido y auto-inicio desactivado${NC}"
            fi
            ;;
        4) docker container prune -f ;;
        5) docker system prune -af ;;
    esac
}

# ============================================
# ESTADO GLOBAL
# ============================================

global_status() {
    clear
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    📊 ESTADO GLOBAL${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e " 🟢 Activos:  $(docker ps -q 2>/dev/null | wc -l)"
    echo -e " 🔴 Detenidos: $(docker ps -a --filter "status=exited" -q 2>/dev/null | wc -l)"
    echo -e " 📦 Total:     $(docker ps -a -q 2>/dev/null | wc -l)"
    echo ""
    echo -e "${CYAN}🎯 Proyectos:${NC}"
    get_projects | while IFS= read -r p; do
        local pattern=$(get_project_pattern "$p")
        local total=$(docker ps -a --filter "name=${pattern}" -q 2>/dev/null | wc -l)
        local running=$(docker ps --filter "name=${pattern}" -q 2>/dev/null | wc -l)
        echo "   $p: $running/$total"
    done
    echo ""
    docker system df 2>/dev/null
    echo ""
    read -p "Presiona Enter..."
}

# ============================================
# MENÚ PRINCIPAL
# ============================================

show_main_menu() {
    clear
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              🐳 GESTOR DE PROYECTOS DOCKER 🐳${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo " 1) 🎯 Gestionar por PROYECTOS"
    echo " 2) 🗺️  Ver mapa de puertos (todos)"
    echo " 3) ⚡ Acciones rápidas"
    echo " 4) 📊 Ver estado global"
    echo " 5) ⭐ Gestionar favoritos"
    echo " 6) 🔍 Búsqueda"
    echo " 7) 🛑🔒 DETENER TODO y desactivar auto-inicio"
    echo " 8) 📜 Ver historial"
    echo " 0) ❌ Salir"
    echo ""
}

show_all_ports() {
    clear
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              🗺️ MAPA DE PUERTOS - TODOS${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo ""
    docker ps --format "table {{.Names}}\t{{.Ports}}" 2>/dev/null
    echo ""
    read -p "Presiona Enter..."
}

show_history() {
    clear
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    📜 HISTORIAL${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo ""
    if [ -f "$HISTORY_FILE" ]; then
        tail -30 "$HISTORY_FILE"
    else
        echo "No hay historial"
    fi
    echo ""
    read -p "Presiona Enter..."
}

stop_all_forever() {
    clear
    echo -e "${RED}════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}         ⚠️  DETENER TODO Y DESACTIVAR AUTO-INICIO${NC}"
    echo -e "${RED}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Esto va a:${NC}"
    echo "  1. Detener todos los contenedores"
    echo "  2. Cambiar política a 'no' (nunca más se inician solos)"
    echo ""
    read -p "Escribe 'CONFIRMAR': " confirm
    if [ "$confirm" = "CONFIRMAR" ]; then
        ids=$(docker ps -q 2>/dev/null); [ -n "$ids" ] && docker stop $ids 2>/dev/null
        docker ps -a -q | while IFS= read -r id; do
            docker update --restart=no "$id" 2>/dev/null
        done
        echo -e "${GREEN}✅ ¡Completado! Los contenedores NO se iniciarán solos${NC}"
        log_action "STOP_ALL_FOREVER" "all"
    fi
}

# ============================================
# INICIO
# ============================================

init_config

while true; do
    show_main_menu
    read -p "➤ Selecciona: " opt
    case $opt in
        1) manage_projects ;;
        2) show_all_ports ;;
        3) quick_actions ;;
        4) global_status ;;
        5) show_favorites ;;
        6) search_containers ;;
        7) stop_all_forever ;;
        8) show_history ;;
        0) echo -e "\n${GREEN}👋 ¡Hasta luego!${NC}"; exit 0 ;;
        *) echo -e "${RED}Opción inválida${NC}"; sleep 1 ;;
    esac
done

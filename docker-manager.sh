#!/bin/bash

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
NC='\033[0m' # No Color

# ============================================
# FUNCIONES DE UTILIDAD
# ============================================

# Extraer nombre del proyecto (primer segmento antes de _ o -)
extract_project_name() {
    local name=$1
    if [[ "$name" == *"_"* ]] || [[ "$name" == *"-"* ]]; then
        echo "$name" | sed -E 's/^([^_-]+)[_-].*/\1/'
    else
        echo "$name"
    fi
}

# Obtener todos los proyectos únicos
get_projects() {
    docker ps -a --format "{{.Names}}" 2>/dev/null | while read name; do
        extract_project_name "$name"
    done | sort -u
}

# Obtener patrón de búsqueda de un proyecto
get_project_pattern() {
    local project=$1
    local has_prefixed=$(docker ps -a --format "{{.Names}}" 2>/dev/null | grep -E "^${project}[_-]" | head -1)
    
    if [ -n "$has_prefixed" ]; then
        if [[ "$has_prefixed" == *"_"* ]]; then
            echo "^${project}_"
        else
            echo "^${project}-"
        fi
    else
        echo "^${project}$"
    fi
}

# Obtener política de reinicio de un contenedor
get_restart_policy() {
    local container=$1
    docker inspect --format='{{.HostConfig.RestartPolicy.Name}}' "$container" 2>/dev/null
}

# ============================================
# FUNCIONES DE VISUALIZACIÓN
# ============================================

# Mostrar todos los proyectos
show_projects() {
    clear
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                        📦 PROYECTOS DETECTADOS${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local index=1
    declare -a projects_array
    
    while IFS= read -r project; do
        if [ -n "$project" ]; then
            projects_array[$index]="$project"
            local pattern=$(get_project_pattern "$project")
            local total=$(docker ps -a --filter "name=${pattern}" --format "{{.Names}}" 2>/dev/null | wc -l)
            local running=$(docker ps --filter "name=${pattern}" --format "{{.Names}}" 2>/dev/null | wc -l)
            
            # Mostrar estado del proyecto
            echo -ne " ${YELLOW}$index)${NC} ${MAGENTA}$project${NC} "
            if [ $total -eq 0 ]; then
                echo -e "- ${RED}● SIN CONTENEDORES${NC}"
            elif [ $running -eq 0 ]; then
                echo -e "- ${RED}● DETENIDO${NC} (0/$total)"
            elif [ $running -eq $total ]; then
                echo -e "- ${GREEN}● COMPLETO${NC} ($running/$total)"
            else
                echo -e "- ${CYAN}● PARCIAL${NC} ($running/$total)"
            fi
            
            # Listar contenedores
            if [ $total -gt 0 ]; then
                docker ps -a --filter "name=${pattern}" --format "     └─ {{.Names}} ({{.Status}})" 2>/dev/null | \
                    sed "s/Up/${GREEN}Up${NC}/g" | \
                    sed "s/Exited/${RED}Exited${NC}/g" | \
                    sed "s/Created/${YELLOW}Created${NC}/g" | \
                    sed "s/healthy/${GREEN}healthy${NC}/g"
            fi
            echo ""
            ((index++))
        fi
    done < <(get_projects)
    
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e " ${YELLOW}0)${NC} 🔙 Volver al menú principal"
    echo ""
}

# Mostrar puertos de un proyecto
show_project_ports() {
    local project=$1
    local pattern=$(get_project_pattern "$project")
    
    clear
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    🔌 PUERTOS DEL PROYECTO: ${MAGENTA}$project${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local containers=$(docker ps -a --filter "name=${pattern}" --format "{{.Names}}" 2>/dev/null)
    
    printf "${YELLOW}%-35s %-40s${NC}\n" "CONTENEDOR" "PUERTOS (host → contenedor)"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    
    echo "$containers" | while read container; do
        if [ -n "$container" ]; then
            local ports=$(docker port "$container" 2>/dev/null)
            
            if [ -n "$ports" ]; then
                echo -e " ${GREEN}▶${NC} ${MAGENTA}$container${NC}"
                echo "$ports" | while read port; do
                    echo -e "    └─ 🔗 ${CYAN}$port${NC}"
                done
            else
                local is_running=$(docker ps --filter "name=$container" -q 2>/dev/null)
                if [ -n "$is_running" ]; then
                    echo -e " ${YELLOW}▶${NC} ${MAGENTA}$container${NC} → ${RED}sin puertos expuestos${NC}"
                else
                    echo -e " ${YELLOW}▶${NC} ${MAGENTA}$container${NC} → ${RED}detenido${NC}"
                fi
            fi
            echo ""
        fi
    done
    
    # Vista rápida con docker ps
    local running_containers=$(docker ps --filter "name=${pattern}" -q 2>/dev/null)
    if [ -n "$running_containers" ]; then
        echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
        echo -e "${YELLOW}📋 Vista rápida (contenedores activos):${NC}"
        echo ""
        docker ps --filter "name=${pattern}" --format "table {{.Names}}\t{{.Ports}}" 2>/dev/null
    fi
    
    echo ""
    echo -e "${YELLOW}Presiona Enter para continuar...${NC}"
    read
}

# Mostrar políticas de reinicio de un proyecto
show_restart_policies() {
    local project=$1
    local pattern=$(get_project_pattern "$project")
    
    clear
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                🔧 POLÍTICAS DE REINICIO - ${MAGENTA}$project${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}📋 ¿Qué significa cada política?${NC}"
    echo -e "   ${WHITE}no${NC}           : No se reinicia automáticamente ${GREEN}✓ RECOMENDADO para dev${NC}"
    echo -e "   ${WHITE}unless-stopped${NC}: Solo reinicia si no lo detuviste manualmente"
    echo -e "   ${WHITE}always${NC}       : Siempre reinicia ${RED}✗ EVITAR en desarrollo${NC}"
    echo -e "   ${WHITE}on-failure${NC}   : Reinicia solo si falla"
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local containers=$(docker ps -a --filter "name=${pattern}" --format "{{.Names}}" 2>/dev/null)
    
    printf "${YELLOW}%-35s %-20s${NC}\n" "CONTENEDOR" "POLÍTICA ACTUAL"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    
    echo "$containers" | while read container; do
        if [ -n "$container" ]; then
            local policy=$(get_restart_policy "$container")
            case "$policy" in
                "always")
                    echo -e " ${RED}⚠️${NC} ${MAGENTA}$container${NC}      ${RED}$policy${NC}"
                    ;;
                "unless-stopped")
                    echo -e " ${GREEN}✅${NC} ${MAGENTA}$container${NC}      ${GREEN}$policy${NC}"
                    ;;
                "on-failure")
                    echo -e " ${YELLOW}🟡${NC} ${MAGENTA}$container${NC}      ${YELLOW}$policy${NC}"
                    ;;
                *)
                    echo -e " ${BLUE}⭕${NC} ${MAGENTA}$container${NC}      ${BLUE}$policy${NC}"
                    ;;
            esac
        fi
    done
    
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
}

# Mapa de puertos global
show_all_ports() {
    clear
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    🗺️  MAPA DE PUERTOS - TODOS LOS PROYECTOS${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local has_ports=false
    
    while IFS= read -r project; do
        if [ -n "$project" ]; then
            local pattern=$(get_project_pattern "$project")
            local containers=$(docker ps --filter "name=${pattern}" --format "{{.Names}}" 2>/dev/null)
            
            if [ -n "$containers" ]; then
                echo -e "${MAGENTA}📦 $project${NC}"
                echo "$containers" | while read container; do
                    local ports=$(docker port "$container" 2>/dev/null)
                    if [ -n "$ports" ]; then
                        has_ports=true
                        echo -e "  └─ ${GREEN}$container${NC}"
                        echo "$ports" | while read port; do
                            echo -e "      └─ 🔗 ${CYAN}$port${NC}"
                        done
                    else
                        echo -e "  └─ ${YELLOW}$container${NC} → sin puertos"
                    fi
                done
                echo ""
            fi
        fi
    done < <(get_projects)
    
    if [ "$has_ports" = false ]; then
        echo -e "${YELLOW}⚠️  No hay contenedores activos con puertos expuestos${NC}"
    fi
    
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}💡 Tip: Los puertos se muestran como IP:PUERTO_HOST → PUERTO_CONTENEDOR${NC}"
    echo ""
    echo -e "${YELLOW}Presiona Enter para continuar...${NC}"
    read
}

# Estado global
global_status() {
    clear
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                        📊 ESTADO GLOBAL DE DOCKER${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local total_containers=$(docker ps -a -q 2>/dev/null | wc -l)
    local running_containers=$(docker ps -q 2>/dev/null | wc -l)
    local stopped_containers=$((total_containers - running_containers))
    
    echo -e "${CYAN}📦 Contenedores:${NC}"
    echo -e "   🟢 Activos: ${GREEN}$running_containers${NC}"
    echo -e "   🔴 Detenidos: ${RED}$stopped_containers${NC}"
    echo -e "   📦 Total: ${YELLOW}$total_containers${NC}"
    echo ""
    
    echo -e "${CYAN}🎯 Proyectos detectados:${NC}"
    while IFS= read -r project; do
        if [ -n "$project" ]; then
            local pattern=$(get_project_pattern "$project")
            local total=$(docker ps -a --filter "name=${pattern}" -q 2>/dev/null | wc -l)
            local running=$(docker ps --filter "name=${pattern}" -q 2>/dev/null | wc -l)
            
            if [ $total -gt 0 ]; then
                if [ $running -eq $total ]; then
                    echo -e "   ${GREEN}●${NC} ${MAGENTA}$project${NC}: $running/$total activos"
                elif [ $running -eq 0 ]; then
                    echo -e "   ${RED}●${NC} ${MAGENTA}$project${NC}: $running/$total activos"
                else
                    echo -e "   ${YELLOW}●${NC} ${MAGENTA}$project${NC}: $running/$total activos"
                fi
            fi
        fi
    done < <(get_projects)
    
    echo ""
    echo -e "${CYAN}💾 Uso de disco Docker:${NC}"
    docker system df 2>/dev/null
    
    echo ""
    echo -e "${YELLOW}Presiona Enter para continuar...${NC}"
    read
}

# ============================================
# FUNCIONES DE ACCIONES SOBRE PROYECTOS
# ============================================

# Iniciar todos los contenedores de un proyecto
start_project() {
    local project=$1
    local pattern=$(get_project_pattern "$project")
    local containers=$(docker ps -a --filter "name=${pattern}" --filter "status=exited" --format "{{.Names}}" 2>/dev/null)
    
    if [ -z "$containers" ]; then
        echo -e "${GREEN}✅ Todos los contenedores del proyecto $project ya están activos${NC}"
    else
        echo -e "${YELLOW}⏳ Iniciando contenedores del proyecto $project...${NC}"
        echo "$containers" | while read container; do
            if [ -n "$container" ]; then
                echo -e "  🚀 Iniciando: $container"
                docker start "$container" > /dev/null 2>&1
            fi
        done
        echo -e "${GREEN}✅ Proyecto $project iniciado${NC}"
    fi
    sleep 2
}

# Detener todos los contenedores de un proyecto
stop_project() {
    local project=$1
    local pattern=$(get_project_pattern "$project")
    local containers=$(docker ps --filter "name=${pattern}" --format "{{.Names}}" 2>/dev/null)
    
    if [ -z "$containers" ]; then
        echo -e "${GREEN}✅ El proyecto $project ya está completamente detenido${NC}"
    else
        echo -e "${YELLOW}⏳ Deteniendo contenedores del proyecto $project...${NC}"
        echo "$containers" | while read container; do
            if [ -n "$container" ]; then
                echo -e "  🛑 Deteniendo: $container"
                docker stop "$container" > /dev/null 2>&1
            fi
        done
        echo -e "${GREEN}✅ Proyecto $project detenido${NC}"
    fi
    sleep 2
}

# Reiniciar proyecto
restart_project() {
    local project=$1
    echo -e "${YELLOW}⏳ Reiniciando proyecto $project...${NC}"
    stop_project "$project"
    sleep 2
    start_project "$project"
    echo -e "${GREEN}✅ Proyecto $project reiniciado${NC}"
    sleep 2
}

# Eliminar proyecto
remove_project() {
    local project=$1
    local pattern=$(get_project_pattern "$project")
    
    echo -e "${RED}⚠️  ¿Estás seguro de que quieres ELIMINAR el proyecto $project?${NC}"
    echo -e "${RED}Esto eliminará TODOS los contenedores:${NC}"
    docker ps -a --filter "name=${pattern}" --format "  - {{.Names}}" 2>/dev/null
    echo ""
    read -p "Escribe 'ELIMINAR' para confirmar: " confirm
    
    if [ "$confirm" = "ELIMINAR" ]; then
        echo -e "${YELLOW}⏳ Eliminando contenedores...${NC}"
        docker rm -f $(docker ps -a --filter "name=${pattern}" -q 2>/dev/null) 2>/dev/null
        echo -e "${GREEN}✅ Proyecto $project eliminado${NC}"
    else
        echo -e "${CYAN}❌ Operación cancelada${NC}"
    fi
    sleep 2
}

# Ver logs del proyecto
logs_project() {
    local project=$1
    local pattern=$(get_project_pattern "$project")
    
    clear
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    📝 LOGS DEL PROYECTO: ${MAGENTA}$project${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local containers=$(docker ps -a --filter "name=${pattern}" --format "{{.Names}}" 2>/dev/null)
    
    echo "$containers" | while read container; do
        if [ -n "$container" ]; then
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${YELLOW}📦 Contenedor: $container${NC}"
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            docker logs --tail=30 "$container" 2>/dev/null
            echo ""
        fi
    done
    
    echo -e "${YELLOW}Presiona Enter para continuar...${NC}"
    read
}

# Ver estado detallado del proyecto
status_project() {
    local project=$1
    local pattern=$(get_project_pattern "$project")
    
    clear
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    📊 ESTADO DEL PROYECTO: ${MAGENTA}$project${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    docker ps -a --filter "name=${pattern}" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null
    
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    
    local running=$(docker ps --filter "name=${pattern}" -q 2>/dev/null)
    if [ -n "$running" ]; then
        echo -e "${YELLOW}📊 Uso de recursos (contenedores activos):${NC}"
        docker stats --no-stream --filter "name=${pattern}" --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null
    fi
    
    echo ""
    echo -e "${YELLOW}Presiona Enter para continuar...${NC}"
    read
}

# Cambiar política de reinicio de un proyecto
change_restart_policy() {
    local project=$1
    local pattern=$(get_project_pattern "$project")
    
    show_restart_policies "$project"
    
    echo ""
    echo -e "${YELLOW}📝 Selecciona la nueva política para TODOS los contenedores:${NC}"
    echo -e "   ${WHITE}1)${NC} no             - No reiniciar automáticamente ${GREEN}✓ RECOMENDADO${NC}"
    echo -e "   ${WHITE}2)${NC} unless-stopped - Reiniciar solo si no fue detenido manualmente"
    echo -e "   ${WHITE}3)${NC} always         - Siempre reiniciar ${RED}✗ EVITAR${NC}"
    echo -e "   ${WHITE}4)${NC} on-failure     - Reiniciar solo en caso de error"
    echo -e "   ${WHITE}0)${NC} Cancelar"
    echo ""
    
    read -p "Opción: " policy_choice
    
    local new_policy=""
    case $policy_choice in
        1) new_policy="no" ;;
        2) new_policy="unless-stopped" ;;
        3) new_policy="always" ;;
        4) new_policy="on-failure" ;;
        0) return ;;
        *) echo -e "${RED}Opción inválida${NC}"; sleep 2; return ;;
    esac
    
    echo ""
    echo -e "${YELLOW}⏳ Aplicando política '${new_policy}' a todos los contenedores...${NC}"
    
    local containers=$(docker ps -a --filter "name=${pattern}" --format "{{.Names}}" 2>/dev/null)
    
    echo "$containers" | while read container; do
        if [ -n "$container" ]; then
            docker update --restart="$new_policy" "$container" > /dev/null 2>&1
            echo -e "  ${GREEN}✓${NC} $container → ${new_policy}"
        fi
    done
    
    echo ""
    echo -e "${GREEN}✅ Política actualizada para todos los contenedores del proyecto${NC}"
    
    if [ "$new_policy" = "no" ]; then
        echo -e "${GREEN}✨ Ahora los contenedores NO se iniciarán automáticamente al abrir WSL${NC}"
    elif [ "$new_policy" = "unless-stopped" ]; then
        echo -e "${GREEN}✨ Los contenedores solo arrancarán si no los detuviste manualmente${NC}"
    fi
    
    sleep 3
}

# Ejecutar docker-compose
compose_project() {
    local project=$1
    local possible_paths=(
        "$HOME/proyectos/$project"
        "$HOME/$project"
        "$HOME/docker/$project"
        "/mnt/c/Users/$USER/projects/$project"
        "/mnt/c/Users/$USER/Documents/projects/$project"
    )
    
    clear
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                🐳 DOCKER-COMPOSE PARA: ${MAGENTA}$project${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local found=false
    for path in "${possible_paths[@]}"; do
        if [ -f "$path/docker-compose.yml" ] || [ -f "$path/docker-compose.yaml" ]; then
            found=true
            echo -e "${GREEN}✅ Encontrado en: ${CYAN}$path${NC}"
            echo ""
            echo -e "${YELLOW}Acciones disponibles:${NC}"
            echo "  1) docker-compose up -d"
            echo "  2) docker-compose down"
            echo "  3) docker-compose restart"
            echo "  4) docker-compose logs"
            echo "  5) Ver docker-compose.yml"
            echo "  0) Cancelar"
            echo ""
            read -p "Selecciona: " compose_action
            
            case $compose_action in
                1) cd "$path" && docker-compose up -d ;;
                2) cd "$path" && docker-compose down ;;
                3) cd "$path" && docker-compose restart ;;
                4) cd "$path" && docker-compose logs --tail=50 ;;
                5) cat "$path/docker-compose.yml" | less ;;
                0) echo "Cancelado" ;;
            esac
            break
        fi
    done
    
    if [ "$found" = false ]; then
        echo -e "${RED}❌ No se encontró docker-compose.yml para $project${NC}"
        echo ""
        echo -e "${YELLOW}Ubicaciones buscadas:${NC}"
        for path in "${possible_paths[@]}"; do
            echo "  - $path"
        done
    fi
    
    echo ""
    read -p "Presiona Enter para continuar..."
}

# Detener TODOS los contenedores y desactivar auto-inicio
stop_all_forever() {
    clear
    echo -e "${RED}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}                ⚠️  DETENER Y DESACTIVAR AUTO-INICIO ⚠️${NC}"
    echo -e "${RED}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Esta acción va a:${NC}"
    echo -e "   1️⃣  Detener TODOS los contenedores activos"
    echo -e "   2️⃣  Cambiar su política a 'no' (no volverán a iniciarse solos)"
    echo ""
    echo -e "${RED}⚠️  ¿Estás completamente seguro?${NC}"
    echo ""
    
    local running_containers=$(docker ps --format "   📦 {{.Names}}" 2>/dev/null)
    if [ -n "$running_containers" ]; then
        echo "$running_containers"
    else
        echo "   ✨ No hay contenedores activos"
    fi
    echo ""
    read -p "Escribe 'CONFIRMAR' para proceder: " confirm
    
    if [ "$confirm" = "CONFIRMAR" ]; then
        echo ""
        echo -e "${YELLOW}⏳ Procesando...${NC}"
        
        local containers=$(docker ps -q 2>/dev/null)
        
        if [ -n "$containers" ]; then
            echo "$containers" | while read container_id; do
                local name=$(docker inspect --format='{{.Name}}' "$container_id" 2>/dev/null | sed 's/^\///')
                echo -e "  🛑 Deteniendo: $name"
                docker stop "$container_id" > /dev/null 2>&1
                docker update --restart=no "$container_id" > /dev/null 2>&1
                echo -e "  ${GREEN}✓${NC} Política cambiada a 'no' para $name"
            done
            echo ""
            echo -e "${GREEN}✅ ¡Completado! Todos los contenedores están detenidos y no volverán a iniciarse solos${NC}"
        else
            echo -e "${GREEN}✅ No había contenedores activos${NC}"
        fi
    else
        echo -e "${CYAN}❌ Operación cancelada${NC}"
    fi
    
    sleep 3
}

# ============================================
# MENÚ DE ACCIONES DEL PROYECTO
# ============================================

show_project_actions() {
    local project=$1
    local pattern=$(get_project_pattern "$project")
    local total=$(docker ps -a --filter "name=${pattern}" --format "{{.Names}}" 2>/dev/null | wc -l)
    local running=$(docker ps --filter "name=${pattern}" --format "{{.Names}}" 2>/dev/null | wc -l)
    
    clear
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    🎯 GESTIONANDO PROYECTO: ${MAGENTA}$project${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ $total -eq 0 ]; then
        echo -e "${RED}⚠️  No hay contenedores para este proyecto${NC}"
        echo ""
        echo -e "${YELLOW}Presiona Enter para continuar...${NC}"
        read
        return 1
    fi
    
    # Barra de estado visual
    local percent=$((running * 100 / total))
    echo -ne " Estado: "
    if [ $running -eq 0 ]; then
        echo -e "${RED}● DETENIDO${NC}"
    elif [ $running -eq $total ]; then
        echo -e "${GREEN}● COMPLETO${NC}"
    else
        echo -e "${YELLOW}● PARCIAL${NC}"
    fi
    echo -e " Contenedores: ${YELLOW}$running/$total activos${NC}"
    echo ""
    
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}  ${YELLOW}1)${NC} 🟢 INICIAR todos           ${YELLOW}5)${NC} 📋 Ver logs                     ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${YELLOW}2)${NC} 🛑 DETENER todos           ${YELLOW}6)${NC} 📊 Ver estado detallado        ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${YELLOW}3)${NC} 🔄 REINICIAR todos         ${YELLOW}7)${NC} 🔌 Ver puertos                 ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${YELLOW}4)${NC} 🗑️  ELIMINAR todos         ${YELLOW}8)${NC} 🔧 Política de reinicio        ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${YELLOW}9)${NC} 🐳 Docker-compose          ${YELLOW}0)${NC} 🔙 Volver                      ${CYAN}│${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    return 0
}

# ============================================
# GESTIÓN PRINCIPAL DE PROYECTOS
# ============================================

manage_projects() {
    while true; do
        show_projects
        
        # Crear array de proyectos
        declare -a projects_list
        while IFS= read -r project; do
            if [ -n "$project" ]; then
                projects_list+=("$project")
            fi
        done < <(get_projects)
        
        if [ ${#projects_list[@]} -eq 0 ]; then
            echo -e "${RED}❌ No hay proyectos detectados${NC}"
            echo -e "${YELLOW}Presiona Enter para continuar...${NC}"
            read
            return
        fi
        
        read -p "Selecciona un proyecto (0 para salir): " project_choice
        
        if [ "$project_choice" = "0" ]; then
            break
        fi
        
        if [[ "$project_choice" =~ ^[0-9]+$ ]] && [ "$project_choice" -ge 1 ] && [ "$project_choice" -le ${#projects_list[@]} ]; then
            local selected_project="${projects_list[$((project_choice-1))]}"
            
            if show_project_actions "$selected_project"; then
                while true; do
                    read -p "➤ Selecciona una acción: " action
                    
                    case $action in
                        1) start_project "$selected_project"; break ;;
                        2) stop_project "$selected_project"; break ;;
                        3) restart_project "$selected_project"; break ;;
                        4) remove_project "$selected_project"; break ;;
                        5) logs_project "$selected_project"; break ;;
                        6) status_project "$selected_project"; break ;;
                        7) show_project_ports "$selected_project"; break ;;
                        8) change_restart_policy "$selected_project"; break ;;
                        9) compose_project "$selected_project"; break ;;
                        0) break ;;
                        *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1 ;;
                    esac
                done
            fi
        else
            echo -e "${RED}❌ Proyecto no válido${NC}"
            sleep 1
        fi
    done
}

# ============================================
# ACCIONES RÁPIDAS
# ============================================

quick_actions() {
    clear
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                        ⚡ ACCIONES RÁPIDAS${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e " ${YELLOW}1)${NC} 🛑 DETENER TODOS los contenedores"
    echo -e " ${YELLOW}2)${NC} 🚀 INICIAR TODOS los contenedores detenidos"
    echo -e " ${YELLOW}3)${NC} 🛑🔒 DETENER TODOS y DESACTIVAR auto-inicio 🆕"
    echo -e " ${YELLOW}4)${NC} 🗑️  Limpiar contenedores detenidos"
    echo -e " ${YELLOW}5)${NC} 🧹 Limpiar todo (contenedores, redes, volúmenes no usados)"
    echo -e " ${YELLOW}0)${NC} 🔙 Volver"
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    
    read -p "Selecciona una opción: " qa_choice
    
    case $qa_choice in
        1) 
            local running=$(docker ps -q 2>/dev/null)
            if [ -n "$running" ]; then
                echo -e "${RED}⚠️  ¿Detener TODOS los contenedores?${NC}"
                read -p "Escribe 'SI' para confirmar: " confirm
                if [ "$confirm" = "SI" ]; then
                    docker stop $(docker ps -q) 2>/dev/null
                    echo -e "${GREEN}✅ Todos los contenedores detenidos${NC}"
                fi
            else
                echo -e "${GREEN}✅ No hay contenedores activos${NC}"
            fi
            sleep 2
            ;;
        2)
            local stopped=$(docker ps -a --filter "status=exited" -q 2>/dev/null)
            if [ -n "$stopped" ]; then
                docker start $stopped 2>/dev/null
                echo -e "${GREEN}✅ Todos los contenedores iniciados${NC}"
            else
                echo -e "${GREEN}✅ No hay contenedores detenidos${NC}"
            fi
            sleep 2
            ;;
        3)
            stop_all_forever
            ;;
        4)
            docker container prune -f 2>/dev/null
            echo -e "${GREEN}✅ Contenedores detenidos eliminados${NC}"
            sleep 2
            ;;
        5)
            echo -e "${YELLOW}⏳ Limpiando recursos no usados...${NC}"
            docker system prune -af 2>/dev/null
            echo -e "${GREEN}✅ Limpieza completada${NC}"
            sleep 2
            ;;
        0) return ;;
        *) echo -e "${RED}Opción inválida${NC}"; sleep 1 ;;
    esac
}

# ============================================
# MENÚ PRINCIPAL
# ============================================

show_main_menu() {
    clear
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    🐳 GESTOR DE PROYECTOS DOCKER 🐳${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e " ${YELLOW}1)${NC} 🎯 Gestionar por PROYECTOS"
    echo -e " ${YELLOW}2)${NC} 🗺️  Ver mapa de puertos (todos los proyectos)"
    echo -e " ${YELLOW}3)${NC} ⚡ Acciones rápidas"
    echo -e " ${YELLOW}4)${NC} 📊 Ver estado global"
    echo -e " ${YELLOW}5)${NC} 🐳 Ver solo contenedores activos"
    echo -e " ${YELLOW}6)${NC} 🔴 Ver solo contenedores detenidos"
    echo -e " ${YELLOW}7)${NC} 🛑🔒 DETENER TODO y desactivar auto-inicio (recomendado)"
    echo -e " ${YELLOW}0)${NC} ❌ Salir"
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
}

# ============================================
# BUCLE PRINCIPAL
# ============================================

while true; do
    show_main_menu
    read -p "➤ Selecciona una opción: " main_choice
    
    case $main_choice in
        1) manage_projects ;;
        2) show_all_ports ;;
        3) quick_actions ;;
        4) global_status ;;
        5) 
            clear
            docker ps 2>/dev/null
            echo ""
            read -p "Presiona Enter para continuar..."
            ;;
        6)
            clear
            docker ps -a --filter "status=exited" 2>/dev/null
            echo ""
            read -p "Presiona Enter para continuar..."
            ;;
        7) stop_all_forever ;;
        0) 
            echo -e "\n${GREEN}👋 ¡Hasta luego!${NC}"
            exit 0
            ;;
        *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1 ;;
    esac
done
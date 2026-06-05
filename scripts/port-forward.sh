#!/bin/bash
# =============================================================================
# PORT-FORWARD INTELIGENTE — Taller Monitoreo Kubernetes
# =============================================================================
# Detecta automáticamente si estás en:
#   - WSL (Windows Subsystem for Linux)
#   - Linux nativo
#   - macOS
#
# Y configura los port-forwards para que sean accesibles desde el navegador
# de Windows en TODOS los casos.
#
# USO:
#   bash scripts/port-forward.sh         # Inicia todos los servicios
#   bash scripts/port-forward.sh stop    # Detiene todos los port-forwards
#   bash scripts/port-forward.sh status  # Ver estado actual
# =============================================================================

set -euo pipefail

# ── Colores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ── Archivo PID para gestionar procesos ───────────────────────────────────────
PID_FILE="/tmp/taller-k8s-portforward.pids"
LOG_DIR="/tmp/taller-k8s-logs"
mkdir -p "$LOG_DIR"

# ── Detección de entorno ──────────────────────────────────────────────────────
detect_environment() {
    if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
        echo "wsl"
    elif [[ "$(uname)" == "Darwin" ]]; then
        echo "macos"
    else
        echo "linux"
    fi
}

ENV_TYPE=$(detect_environment)

# En WSL necesitamos --address 0.0.0.0 para que Windows pueda acceder
# En Linux/macOS nativo, 127.0.0.1 es suficiente
if [[ "$ENV_TYPE" == "wsl" ]]; then
    BIND_ADDRESS="0.0.0.0"
    BROWSER_HOST="localhost"
else
    BIND_ADDRESS="127.0.0.1"
    BROWSER_HOST="localhost"
fi

# ── Configuración de servicios ────────────────────────────────────────────────
declare -A SERVICES
# Formato: "nombre|namespace|svc-name|local-port|remote-port|descripcion"
GRAFANA_SVC="grafana|monitoring|monitoring-grafana|3000|80|📊 Grafana Dashboards"
PROMETHEUS_SVC="prometheus|monitoring|monitoring-kube-prometheus-prometheus|9090|9090|🔥 Prometheus"
ORDER_API_SVC="order-api|taller-monitoreo|order-api|5000|5000|📦 order-api"
INVENTORY_SVC="inventory|taller-monitoreo|inventory-service|3001|3000|🏭 inventory-service"

ALL_SERVICES=("$GRAFANA_SVC" "$PROMETHEUS_SVC" "$ORDER_API_SVC" "$INVENTORY_SVC")

# ── Imprimir banner ───────────────────────────────────────────────────────────
print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║   🎓 TALLER: MONITOREO KUBERNETES                       ║"
    echo "║      Port-Forward Manager                               ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  Entorno detectado: ${YELLOW}${ENV_TYPE^^}${NC}"
    echo -e "  Bind address:      ${YELLOW}${BIND_ADDRESS}${NC}"
    echo ""
}

# ── Verificar que K8s está disponible ────────────────────────────────────────
check_kubernetes() {
    if ! kubectl cluster-info &>/dev/null; then
        echo -e "${RED}[ERROR] No se puede conectar al cluster de Kubernetes.${NC}"
        echo ""
        echo "Posibles causas:"
        echo "  - Minikube no está corriendo: ejecuta 'minikube start'"
        echo "  - Docker Desktop: activa Kubernetes en Settings → Kubernetes"
        echo ""
        exit 1
    fi
    echo -e "${GREEN}[✅ OK] Conectado al cluster Kubernetes${NC}"
}

# ── Matar port-forwards existentes ────────────────────────────────────────────
kill_existing() {
    if [[ -f "$PID_FILE" ]]; then
        echo -e "${YELLOW}[INFO] Deteniendo port-forwards anteriores...${NC}"
        while IFS= read -r pid; do
            kill "$pid" 2>/dev/null && echo "  Detenido PID $pid" || true
        done < "$PID_FILE"
        rm -f "$PID_FILE"
    fi

    # También matar por nombre de proceso por si acaso
    pkill -f "kubectl port-forward" 2>/dev/null || true
    sleep 1
}

# ── Esperar a que un puerto esté disponible ────────────────────────────────────
wait_for_port() {
    local port=$1
    local name=$2
    local max_attempts=20
    local attempt=0

    while ! nc -z localhost "$port" 2>/dev/null; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            echo -e "  ${RED}[TIMEOUT]${NC} $name no responde en puerto $port"
            return 1
        fi
        sleep 0.5
    done
    return 0
}

# ── Iniciar un port-forward individual ────────────────────────────────────────
start_port_forward() {
    local config=$1
    IFS='|' read -r name namespace svc local_port remote_port description <<< "$config"

    # Verificar si el service existe
    if ! kubectl get svc "$svc" -n "$namespace" &>/dev/null; then
        echo -e "  ${YELLOW}[SKIP]${NC} $description — Service no encontrado en namespace '$namespace'"
        return 0
    fi

    local log_file="$LOG_DIR/${name}.log"

    echo -ne "  Iniciando $description (localhost:${local_port})... "

    kubectl port-forward \
        "svc/${svc}" \
        "${local_port}:${remote_port}" \
        -n "$namespace" \
        --address "$BIND_ADDRESS" \
        > "$log_file" 2>&1 &

    local pid=$!
    echo "$pid" >> "$PID_FILE"

    # Esperar a que el puerto esté listo
    if wait_for_port "$local_port" "$description"; then
        echo -e "${GREEN}OK${NC} (PID: $pid)"
    else
        echo -e "${YELLOW}lento, puede tardar unos segundos${NC}"
    fi
}

# ── Mostrar URLs de acceso ─────────────────────────────────────────────────────
show_urls() {
    echo ""
    echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  🌐 SERVICIOS DISPONIBLES — Abre en tu navegador:${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  📊 Grafana           → ${CYAN}http://${BROWSER_HOST}:3000${NC}"
    echo -e "                         Usuario: ${YELLOW}admin${NC}  Contraseña: ${YELLOW}taller2024${NC}"
    echo ""
    echo -e "  🔥 Prometheus        → ${CYAN}http://${BROWSER_HOST}:9090${NC}"
    echo -e "                         Ver targets: ${CYAN}http://${BROWSER_HOST}:9090/targets${NC}"
    echo ""
    echo -e "  📦 order-api         → ${CYAN}http://${BROWSER_HOST}:5000${NC}"
    echo -e "                         Health: ${CYAN}http://${BROWSER_HOST}:5000/health${NC}"
    echo -e "                         Métricas: ${CYAN}http://${BROWSER_HOST}:5000/metrics${NC}"
    echo ""
    echo -e "  🏭 inventory-service → ${CYAN}http://${BROWSER_HOST}:3001${NC}"
    echo -e "                         Health: ${CYAN}http://${BROWSER_HOST}:3001/health${NC}"
    echo -e "                         Inventario: ${CYAN}http://${BROWSER_HOST}:3001/inventory${NC}"
    echo ""
    echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
    echo ""

    if [[ "$ENV_TYPE" == "wsl" ]]; then
        echo -e "  ${YELLOW}💡 WSL detectado: los servicios son accesibles desde${NC}"
        echo -e "  ${YELLOW}   Windows Browser usando 'localhost'${NC}"
        echo ""
    fi

    echo -e "  ${MAGENTA}💥 CASUÍSTICAS (en otra terminal):${NC}"
    echo -e "  bash load-testing/stress-test.sh memory   # Casuística 2: Memory Leak"
    echo -e "  bash load-testing/stress-test.sh load     # Casuística 3: HPA Storm"
    echo -e "  bash load-testing/chaos-delay.sh enable   # Casuística 4: Slow Service"
    echo -e "  bash load-testing/stress-test.sh drain    # Casuística 5: Stock Zero"
    echo ""
    echo -e "  Presiona ${RED}Ctrl+C${NC} para detener todos los port-forwards."
    echo ""
}

# ── Monitoreo en vivo de los procesos ─────────────────────────────────────────
monitor_processes() {
    echo -e "${BLUE}[INFO] Monitoreando port-forwards... (Ctrl+C para salir)${NC}"
    echo ""

    while true; do
        sleep 10

        # Verificar que los procesos siguen vivos
        local dead=false
        if [[ -f "$PID_FILE" ]]; then
            while IFS= read -r pid; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    echo -e "${YELLOW}[WARN] Port-forward PID $pid murió. Reiniciando...${NC}"
                    dead=true
                fi
            done < "$PID_FILE"
        fi

        if [[ "$dead" == "true" ]]; then
            echo -e "${YELLOW}[INFO] Reiniciando port-forwards caídos...${NC}"
            rm -f "$PID_FILE"
            touch "$PID_FILE"
            for svc_config in "${ALL_SERVICES[@]}"; do
                start_port_forward "$svc_config"
            done
        fi
    done
}

# ── Limpieza al salir (Ctrl+C) ────────────────────────────────────────────────
cleanup() {
    echo ""
    echo -e "${YELLOW}[INFO] Deteniendo todos los port-forwards...${NC}"
    kill_existing
    echo -e "${GREEN}[OK] Todos los port-forwards detenidos. ¡Hasta la próxima clase!${NC}"
    exit 0
}

# ── Subcomando: status ────────────────────────────────────────────────────────
show_status() {
    echo -e "${CYAN}Estado de los port-forwards:${NC}"
    echo ""

    local ports=(3000 9090 5000 3001)
    local names=("Grafana" "Prometheus" "order-api" "inventory-service")

    for i in "${!ports[@]}"; do
        local port="${ports[$i]}"
        local name="${names[$i]}"
        if nc -z localhost "$port" 2>/dev/null; then
            echo -e "  ${GREEN}[UP]${NC}   $name → http://localhost:$port"
        else
            echo -e "  ${RED}[DOWN]${NC} $name → puerto $port no responde"
        fi
    done
    echo ""
}

# ── MAIN ──────────────────────────────────────────────────────────────────────
COMMAND="${1:-start}"

case "$COMMAND" in
    "stop")
        echo -e "${YELLOW}Deteniendo port-forwards del taller...${NC}"
        kill_existing
        echo -e "${GREEN}✅ Detenidos${NC}"
        exit 0
        ;;
    "status")
        show_status
        exit 0
        ;;
    "start"|*)
        print_banner
        check_kubernetes

        echo ""
        echo -e "${BLUE}[INFO] Iniciando port-forwards...${NC}"
        echo ""

        # Limpiar procesos anteriores
        kill_existing
        touch "$PID_FILE"

        # Iniciar cada servicio
        for svc_config in "${ALL_SERVICES[@]}"; do
            start_port_forward "$svc_config"
        done

        # Mostrar URLs
        show_urls

        # Registrar cleanup para Ctrl+C
        trap cleanup SIGINT SIGTERM

        # Monitorear y auto-reiniciar si algún proceso muere
        monitor_processes
        ;;
esac

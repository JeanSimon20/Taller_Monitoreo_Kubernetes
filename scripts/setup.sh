#!/bin/bash
# =============================================================================
# SETUP COMPLETO DEL TALLER — Kubernetes Monitoring Workshop
# =============================================================================
# PROFESOR DICE: Este script es el "boton mágico" del taller.
# Ejecuta UNA VEZ y todo el entorno queda listo para la clase.
#
# PREREQUISITOS:
#   - Docker Desktop instalado y corriendo
#   - Minikube instalado
#   - kubectl instalado
#   - Helm instalado
#
# TIEMPO ESTIMADO: ~5-8 minutos (descarga de imágenes de Helm incluida)
#
# USO:
#   bash scripts/setup.sh
# =============================================================================

set -euo pipefail  # Detener si hay error (-e), variable no definida (-u), pipe falla (-o pipefail)

# ── Colores para output legible ───────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ── Funciones de logging ──────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✅ OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[⚠️  WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[❌ ERROR]${NC} $1"; }
log_step()    { echo -e "\n${CYAN}══════════════════════════════════════${NC}"; echo -e "${CYAN} 🎯 $1${NC}"; echo -e "${CYAN}══════════════════════════════════════${NC}"; }

# ── Verificación de prerequisitos ─────────────────────────────────────────────
check_prerequisites() {
    log_step "Verificando prerequisitos"

    local tools=("docker" "minikube" "kubectl" "helm")
    local missing=()

    for tool in "${tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            log_success "$tool encontrado: $(command -v $tool)"
        else
            log_error "$tool NO está instalado"
            missing+=("$tool")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Faltan herramientas: ${missing[*]}"
        log_error "Por favor instálalas antes de continuar."
        exit 1
    fi

    log_success "Todos los prerequisitos están instalados"
}

# ── Iniciar Minikube ──────────────────────────────────────────────────────────
start_minikube() {
    log_step "Iniciando Minikube"

    if minikube status &>/dev/null; then
        log_success "Minikube ya está corriendo"
    else
        log_info "Iniciando Minikube con recursos suficientes para el taller..."
        # PROFESOR DICE: El taller necesita al menos 4GB de RAM y 2 CPUs
        # para correr Prometheus + Grafana + los 2 microservicios sin problemas.
        minikube start \
            --cpus=4 \
            --memory=6144 \
            --disk-size=20g \
            --driver=docker

        log_success "Minikube iniciado correctamente"
    fi

    # Habilitamos metrics-server (necesario para el HPA en Casuística 3)
    log_info "Habilitando metrics-server para el HPA..."
    minikube addons enable metrics-server
    log_success "metrics-server habilitado"
}

# ── Build de imágenes Docker en Minikube ─────────────────────────────────────
build_images() {
    log_step "Construyendo imágenes Docker"

    # PROFESOR DICE: Este es el truco más importante para Minikube.
    # 'eval $(minikube docker-env)' apunta el cliente Docker al daemon
    # que corre DENTRO de Minikube. Así cuando K8s busca la imagen,
    # la encuentra localmente sin necesitar Docker Hub.
    log_info "Configurando Docker para apuntar a Minikube..."
    eval "$(minikube docker-env)"

    # Limpiamos imágenes viejas para evitar conflictos de caché
    log_info "Eliminando imágenes anteriores si existen..."
    docker rmi order-api:latest 2>/dev/null || true
    docker rmi inventory-service:latest 2>/dev/null || true

    log_info "Construyendo order-api (Python/Flask)..."
    docker build --no-cache --progress=plain -t order-api:latest ./microservices/order-api/
    log_success "order-api:latest construida"

    log_info "Construyendo inventory-service (Node.js)..."
    docker build --no-cache --progress=plain -t inventory-service:latest ./microservices/inventory-service/
    log_success "inventory-service:latest construida"

    log_info "Imágenes disponibles en Minikube:"
    docker images | grep -E "order-api|inventory-service"
}

# ── Crear Namespace ───────────────────────────────────────────────────────────
create_namespace() {
    log_step "Creando namespace del taller"

    kubectl apply -f k8s/namespace.yaml
    log_success "Namespace 'taller-monitoreo' creado"
}

# ── Instalar Stack de Monitoreo con Helm ─────────────────────────────────────
install_monitoring() {
    log_step "Instalando Prometheus + Grafana (kube-prometheus-stack)"

    # Agregar repositorio de Helm si no existe
    if ! helm repo list | grep -q "prometheus-community"; then
        log_info "Agregando repositorio prometheus-community..."
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    fi
    helm repo update

    # Instalar o actualizar el stack de monitoreo
    if helm list -n monitoring | grep -q "monitoring"; then
        log_info "Stack de monitoreo ya instalado, actualizando..."
        helm upgrade monitoring prometheus-community/kube-prometheus-stack \
            --namespace monitoring \
            --values k8s/monitoring/prometheus-values.yaml \
            --wait \
            --timeout 10m
    else
        log_info "Instalando kube-prometheus-stack (esto toma ~3-5 minutos)..."
        helm install monitoring prometheus-community/kube-prometheus-stack \
            --namespace monitoring \
            --create-namespace \
            --values k8s/monitoring/prometheus-values.yaml \
            --wait \
            --timeout 10m
    fi

    log_success "Stack de monitoreo instalado correctamente"
}

# ── Desplegar Microservicios ──────────────────────────────────────────────────
deploy_microservices() {
    log_step "Desplegando microservicios"

    log_info "Desplegando inventory-service (primero, porque order-api depende de él)..."
    kubectl apply -f k8s/inventory-service/deployment.yaml
    kubectl apply -f k8s/inventory-service/service.yaml

    log_info "Desplegando order-api..."
    kubectl apply -f k8s/order-api/deployment.yaml
    kubectl apply -f k8s/order-api/service.yaml
    kubectl apply -f k8s/order-api/hpa.yaml

    log_info "Esperando que los pods estén listos..."
    kubectl rollout status deployment/inventory-service -n taller-monitoreo --timeout=120s
    kubectl rollout status deployment/order-api -n taller-monitoreo --timeout=120s

    log_success "Microservicios desplegados correctamente"
}

# ── Aplicar Configuración de Monitoreo ───────────────────────────────────────
apply_monitoring_config() {
    log_step "Configurando ServiceMonitors y Alertas"

    kubectl apply -f k8s/monitoring/servicemonitor-order.yaml
    kubectl apply -f k8s/monitoring/servicemonitor-inventory.yaml
    kubectl apply -f k8s/monitoring/alerting-rules.yaml

    log_success "ServiceMonitors y alertas configurados"
}

# ── Importar Dashboard de Grafana ────────────────────────────────────────────
import_grafana_dashboard() {
    log_step "Importando Dashboard de Grafana"

    log_info "Esperando que Grafana esté listo..."
    kubectl wait --for=condition=ready pod \
        -l "app.kubernetes.io/name=grafana" \
        -n monitoring \
        --timeout=120s

    # Port-forward temporal para subir el dashboard
    log_info "Subiendo dashboard via API de Grafana..."
    kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring &
    PF_PID=$!
    sleep 5

    # Subir el dashboard via API REST de Grafana
    DASHBOARD_PAYLOAD=$(cat k8s/monitoring/grafana-dashboard.json)
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"dashboard\": ${DASHBOARD_PAYLOAD}, \"overwrite\": true, \"folderId\": 0}" \
        "http://admin:taller2024@localhost:3000/api/dashboards/db" \
        | python3 -m json.tool || true

    kill $PF_PID 2>/dev/null || true
    log_success "Dashboard importado en Grafana"
}

# ── Verificación Final ────────────────────────────────────────────────────────
verify_setup() {
    log_step "Verificación del entorno"

    echo ""
    log_info "Estado de los pods en 'taller-monitoreo':"
    kubectl get pods -n taller-monitoreo -o wide

    echo ""
    log_info "Estado de los pods de monitoreo:"
    kubectl get pods -n monitoring --no-headers | head -10

    echo ""
    log_info "Services disponibles:"
    kubectl get services -n taller-monitoreo

    echo ""
    log_info "HPA (Horizontal Pod Autoscaler):"
    kubectl get hpa -n taller-monitoreo

    echo ""
    log_info "ServiceMonitors configurados:"
    kubectl get servicemonitors -n taller-monitoreo

    echo ""
    log_info "PrometheusRules (alertas):"
    kubectl get prometheusrules -n taller-monitoreo
}

# ── Mostrar URLs de Acceso ────────────────────────────────────────────────────
show_access_info() {
    log_step "¡Taller listo! 🎉 URLs de acceso"

    MINIKUBE_IP=$(minikube ip)

    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  🌐 URLS DE ACCESO AL TALLER${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  📦 order-api:           ${CYAN}http://${MINIKUBE_IP}:30500${NC}"
    echo -e "  🏭 inventory-service:   ${CYAN}http://${MINIKUBE_IP}:30300${NC}"
    echo ""
    echo -e "  Para Grafana y Prometheus, usa port-forward:"
    echo -e "  📊 Grafana:    ${CYAN}kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring${NC}"
    echo -e "               ${CYAN}http://localhost:3000${NC} (admin / taller2024)"
    echo ""
    echo -e "  🔥 Prometheus: ${CYAN}kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090 -n monitoring${NC}"
    echo -e "               ${CYAN}http://localhost:9090${NC}"
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  🧪 Para verificar las métricas:"
    echo -e "  ${YELLOW}curl http://${MINIKUBE_IP}:30500/metrics${NC}"
    echo -e "  ${YELLOW}curl http://${MINIKUBE_IP}:30300/metrics${NC}"
    echo ""
    echo -e "  💥 Para ejecutar las casuísticas:"
    echo -e "  ${YELLOW}bash load-testing/stress-test.sh${NC}       # Casuísticas 2 y 3"
    echo -e "  ${YELLOW}bash load-testing/chaos-delay.sh enable${NC} # Casuística 4"
    echo ""
}

# ── MAIN ──────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   🎓 TALLER: MONITOREO KUBERNETES                     ║${NC}"
    echo -e "${CYAN}║      Prometheus + Grafana + Microservicios             ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Navegamos al directorio raíz del proyecto
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$SCRIPT_DIR/.."

    check_prerequisites
    start_minikube
    build_images
    create_namespace
    install_monitoring
    deploy_microservices
    apply_monitoring_config
    import_grafana_dashboard
    verify_setup
    show_access_info
}

main "$@"

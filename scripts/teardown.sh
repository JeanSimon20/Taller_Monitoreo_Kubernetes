#!/bin/bash
# =============================================================================
# TEARDOWN — Limpieza completa del entorno
# =============================================================================
# Elimina todos los recursos del taller de Kubernetes.
# Útil para: reset entre clases, liberar recursos, empezar de cero.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  🧹 TEARDOWN — Limpiando entorno del taller     ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
echo ""

OPTION=${1:-"partial"}

case "$OPTION" in
    "full")
        echo -e "${YELLOW}⚠️  TEARDOWN COMPLETO: eliminando Minikube entero${NC}"
        read -p "¿Estás seguro? (yes/no): " -r
        if [ "$REPLY" = "yes" ]; then
            minikube delete
            echo -e "${GREEN}✅ Minikube eliminado${NC}"
        fi
        ;;
    "partial"|*)
        echo "Eliminando microservicios..."
        kubectl delete -f k8s/order-api/ -n taller-monitoreo --ignore-not-found
        kubectl delete -f k8s/inventory-service/ -n taller-monitoreo --ignore-not-found
        kubectl delete -f k8s/monitoring/ -n taller-monitoreo --ignore-not-found

        echo "Desinstalando stack de monitoreo..."
        helm uninstall monitoring -n monitoring 2>/dev/null || true

        echo "Eliminando namespace..."
        kubectl delete namespace taller-monitoreo --ignore-not-found
        kubectl delete namespace monitoring --ignore-not-found

        echo ""
        echo -e "${GREEN}✅ Entorno limpio. Para reinstalar: bash scripts/setup.sh${NC}"
        ;;
esac

#!/bin/bash
# =============================================================================
# TEARDOWN — Limpieza completa del entorno
# =============================================================================
# Elimina todos los recursos del taller de Kubernetes.
# Útil para: reset entre clases, liberar recursos, empezar de cero.
#
# USO:
#   bash scripts/teardown.sh           # Limpieza parcial (solo taller-monitoreo)
#   bash scripts/teardown.sh full      # Borra Minikube entero
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  🧹 TEARDOWN — Limpiando entorno del taller     ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
echo ""

OPTION=${1:-"partial"}

# ── PASO 0: Matar port-forwards activos ──────────────────────────────────────
# BUG FIX: sin esto los procesos kubectl port-forward quedan como zombies
# apuntando a pods que ya no existen.
echo -e "${YELLOW}[1/5] Deteniendo port-forwards activos...${NC}"
pkill -f "kubectl port-forward" 2>/dev/null && echo "  Port-forwards detenidos" || echo "  No había port-forwards activos"
sleep 1

case "$OPTION" in
    "full")
        echo -e "${YELLOW}⚠️  TEARDOWN COMPLETO: eliminando Minikube entero${NC}"
        # BUG FIX: read -p sin variable destino usa $REPLY, pero no es portable.
        # Usamos 'read -r CONFIRM' para garantizar que funcione en bash/zsh/dash.
        read -r -p "¿Estás seguro? Esto borra TODO Minikube (yes/no): " CONFIRM
        if [ "$CONFIRM" = "yes" ]; then
            minikube delete
            echo -e "${GREEN}✅ Minikube eliminado completamente${NC}"
        else
            echo "Cancelado."
            exit 0
        fi
        ;;

    "partial"|*)
        # ── PASO 1: Reset casuísticas activas ────────────────────────────────
        # BUG FIX: si quedó chaos activo, el rolling restart de inventory-service
        # al reinstalar puede tardar mucho o fallar. Lo limpiamos primero.
        echo -e "${YELLOW}[2/5] Reseteando casuísticas activas...${NC}"
        kubectl set env deployment/inventory-service CHAOS_DELAY_MS=0 \
            -n taller-monitoreo 2>/dev/null && echo "  Chaos delay reseteado a 0ms" || true

        # ── PASO 2: Borrar microservicios ─────────────────────────────────────
        # BUG FIX: quitamos '-n taller-monitoreo' de 'kubectl delete -f' porque
        # el flag -n es ignorado cuando los manifiestos ya definen su namespace.
        # Lo correcto es dejar que cada YAML aplique su propio namespace.
        echo -e "${YELLOW}[3/5] Eliminando microservicios...${NC}"
        kubectl delete -f k8s/order-api/     --ignore-not-found 2>/dev/null || true
        kubectl delete -f k8s/inventory-service/ --ignore-not-found 2>/dev/null || true
        kubectl delete -f k8s/monitoring/    --ignore-not-found 2>/dev/null || true
        echo "  Microservicios eliminados"

        # ── PASO 3: Desinstalar Helm ANTES de borrar el namespace ─────────────
        # BUG FIX: el orden importa. Si borramos el namespace primero y luego
        # hacemos helm uninstall, Helm falla porque el namespace ya no existe.
        echo -e "${YELLOW}[4/5] Desinstalando stack de monitoreo (Helm)...${NC}"
        helm uninstall monitoring -n monitoring 2>/dev/null \
            && echo "  Helm release 'monitoring' eliminado" \
            || echo "  (release 'monitoring' no encontrado, continuando)"

        # ── PASO 4: Borrar namespaces ─────────────────────────────────────────
        echo -e "${YELLOW}[5/5] Eliminando namespaces...${NC}"
        kubectl delete namespace taller-monitoreo --ignore-not-found 2>/dev/null || true
        kubectl delete namespace monitoring        --ignore-not-found 2>/dev/null || true
        echo "  Namespaces eliminados"

        echo ""
        echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  ✅ Entorno limpio.${NC}"
        echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "  Para reinstalar desde cero:"
        echo -e "  ${CYAN}bash scripts/setup.sh${NC}"
        echo ""
        ;;
esac

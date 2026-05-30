#!/bin/bash
# =============================================================================
# CHAOS DELAY — Script de Casuística 4: El Servicio Lento
# =============================================================================
# PROFESOR DICE: Este script inyecta un delay artificial en inventory-service
# usando la variable de entorno CHAOS_DELAY_MS.
#
# Cuando activamos el delay, order-api empieza a recibir timeouts
# porque su timeout está configurado a 3 segundos y el inventory-service
# tarda más. Esto se ve EN TIEMPO REAL en Grafana.
#
# USO:
#   bash load-testing/chaos-delay.sh enable   # Inyectar delay de 2 segundos
#   bash load-testing/chaos-delay.sh disable  # Volver a comportamiento normal
#   bash load-testing/chaos-delay.sh status   # Ver configuración actual
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

NAMESPACE="taller-monitoreo"
MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "192.168.49.2")
ORDER_API_URL="http://${MINIKUBE_IP}:30500"

case "${1:-status}" in
    "enable")
        DELAY=${2:-2000}  # Default: 2 segundos
        echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  💥 CASUÍSTICA 4: EL SERVICIO LENTO             ║${NC}"
        echo -e "${RED}║  Inyectando delay de ${DELAY}ms en inventory-service ║${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}👁️  OBSERVA EN GRAFANA:${NC}"
        echo "   Panel: '⏱️ Latencia de Reservas — inventory-service'"
        echo "   Panel: '⚠️ Timeouts Inventario'"
        echo "   La latencia del inventory-service subirá a ~${DELAY}ms"
        echo "   order-api empezará a reportar timeouts después de 3s"
        echo ""
        echo -e "${YELLOW}TAMBIÉN EJECUTA EN OTRA TERMINAL:${NC}"
        echo -e "${CYAN}   watch -n 2 \"curl -s ${ORDER_API_URL}/metrics | grep inventory_service_calls\"${NC}"
        echo ""

        # PROFESOR DICE: kubectl set env es la forma más rápida de cambiar
        # una variable de entorno sin editar el YAML. K8s hace rolling restart.
        kubectl set env deployment/inventory-service \
            CHAOS_DELAY_MS="${DELAY}" \
            -n "${NAMESPACE}"

        echo -e "${YELLOW}⏳ Esperando que el pod se reinicie con el nuevo delay...${NC}"
        kubectl rollout status deployment/inventory-service -n "${NAMESPACE}" --timeout=60s

        echo ""
        echo -e "${RED}💥 CHAOS ACTIVO — inventory-service tiene ${DELAY}ms de delay${NC}"
        echo ""
        echo "Para generar tráfico y ver los timeouts:"
        echo -e "${CYAN}  for i in {1..20}; do curl -s -X POST ${ORDER_API_URL}/orders -H 'Content-Type: application/json' -d '{\"product_id\":\"laptop-01\",\"quantity\":1}'; echo; sleep 1; done${NC}"
        ;;

    "disable")
        echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✅ DESACTIVANDO CHAOS — Volviendo a normal     ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
        echo ""

        kubectl set env deployment/inventory-service \
            CHAOS_DELAY_MS=0 \
            -n "${NAMESPACE}"

        kubectl rollout status deployment/inventory-service -n "${NAMESPACE}" --timeout=60s

        echo ""
        echo -e "${GREEN}✅ inventory-service vuelve a comportamiento normal${NC}"
        echo "Verifica en Grafana que la latencia baje en los próximos 15-30 segundos."
        ;;

    "status")
        echo -e "${CYAN}Estado actual de chaos:${NC}"
        kubectl get deployment inventory-service \
            -n "${NAMESPACE}" \
            -o jsonpath='{.spec.template.spec.containers[0].env}'
        echo ""
        ;;

    *)
        echo "Uso: $0 [enable|disable|status] [delay_ms]"
        echo ""
        echo "Ejemplos:"
        echo "  $0 enable 2000   # Delay de 2 segundos"
        echo "  $0 enable 5000   # Delay de 5 segundos (órdenes empezarán a fallar)"
        echo "  $0 disable       # Volver a normal"
        ;;
esac

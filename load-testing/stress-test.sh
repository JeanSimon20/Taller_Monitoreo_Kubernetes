#!/bin/bash
# =============================================================================
# STRESS TEST — Scripts de Carga para Casuísticas 2 y 3
# =============================================================================
# PROFESOR DICE: Usamos curl en un bucle para simular carga.
# En producción usarías k6, Locust o JMeter, pero para el taller
# un script de bash es suficiente y sin dependencias adicionales.
#
# CASUÍSTICA 2 — MEMORY LEAK:
#   Llama al endpoint /orders/stress que acumula datos en memoria
#
# CASUÍSTICA 3 — TORMENTA DE REQUESTS:
#   Genera carga masiva para que el HPA escale los pods
#
# USO:
#   bash load-testing/stress-test.sh [casuistica] [iteraciones]
#   bash load-testing/stress-test.sh memory 100
#   bash load-testing/stress-test.sh load 500
#   bash load-testing/stress-test.sh orders 50
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "192.168.49.2")
ORDER_API_URL="http://${MINIKUBE_IP}:30500"
INVENTORY_URL="http://${MINIKUBE_IP}:30300"

# Lista de productos del inventario para crear órdenes reales
PRODUCTS=("laptop-01" "mouse-01" "kb-01" "monitor-01" "headset-01")

# ── Función: Casuística 2 — Memory Leak ─────────────────────────────────────
run_memory_leak() {
    local iterations=${1:-100}
    echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  💥 CASUÍSTICA 2: FUGA DE MEMORIA               ║${NC}"
    echo -e "${RED}║  Llamando /orders/stress ${iterations} veces             ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}👁️  OBSERVA EN GRAFANA:${NC}"
    echo "   Panel: '🧠 Memory Leak (Casuística 2)'"
    echo "   Métrica: memory_leak_simulation_bytes"
    echo "   Verás cómo sube linealmente hasta el límite de 256MB"
    echo ""
    echo -e "${YELLOW}⚠️  Alerta 'HighMemoryUsage' disparará cuando supere el 85%${NC}"
    echo ""

    read -p "Presiona ENTER para iniciar... " -r

    for i in $(seq 1 "$iterations"); do
        RESPONSE=$(curl -s -w " | HTTP:%{http_code}" "${ORDER_API_URL}/orders/stress")
        echo -e "  [${i}/${iterations}] ${RESPONSE}"
        sleep 0.5
    done

    echo ""
    echo -e "${GREEN}✅ Memory leak simulado. Verifica el panel en Grafana.${NC}"
    echo -e "${CYAN}Para limpiar: curl -X POST ${ORDER_API_URL}/orders/reset-stress${NC}"
}

# ── Función: Casuística 3 — Tormenta de Requests ────────────────────────────
run_load_storm() {
    local iterations=${1:-500}
    echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  💥 CASUÍSTICA 3: TORMENTA DE REQUESTS          ║${NC}"
    echo -e "${RED}║  Generando ${iterations} requests concurrentes           ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}👁️  OBSERVA EN GRAFANA:${NC}"
    echo "   Panel: '⚡ Uso de CPU — Casuística 3'"
    echo "   Panel: '🔢 Pods Running — order-api (HPA)'"
    echo "   El CPU superará el 70% → HPA escala pods automáticamente"
    echo ""
    echo -e "${YELLOW}TAMBIÉN EJECUTA EN OTRA TERMINAL:${NC}"
    echo -e "${CYAN}   kubectl get hpa -n taller-monitoreo --watch${NC}"
    echo ""

    read -p "Presiona ENTER para iniciar la tormenta... " -r

    echo -e "${RED}🌊 ¡INICIANDO TORMENTA DE REQUESTS!${NC}"

    # Ejecutamos requests en paralelo usando background jobs
    SUCCESS=0
    FAILED=0

    for i in $(seq 1 "$iterations"); do
        # Request en background para paralelismo
        (
            PRODUCT=${PRODUCTS[$((RANDOM % ${#PRODUCTS[@]}))]}
            QUANTITY=$((RANDOM % 3 + 1))
            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
                -X POST \
                -H "Content-Type: application/json" \
                -d "{\"product_id\": \"${PRODUCT}\", \"quantity\": ${QUANTITY}}" \
                "${ORDER_API_URL}/orders" \
                --max-time 5)

            if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "409" ]; then
                echo -ne "${GREEN}.${NC}"
            else
                echo -ne "${RED}x${NC}"
            fi
        ) &

        # Cada 20 requests, esperamos un poco para no saturar el sistema de demo
        if (( i % 20 == 0 )); then
            wait
            echo " [$i/$iterations]"
            sleep 0.2
        fi
    done

    wait
    echo ""
    echo ""
    echo -e "${GREEN}✅ Tormenta completada. Observa cómo el HPA reduce los pods en ~5 minutos.${NC}"
}

# ── Función: Crear Órdenes Reales ─────────────────────────────────────────────
run_orders() {
    local count=${1:-20}
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  🛒 CREANDO ${count} ÓRDENES REALES                   ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    for i in $(seq 1 "$count"); do
        PRODUCT=${PRODUCTS[$((RANDOM % ${#PRODUCTS[@]}))]}
        QUANTITY=$((RANDOM % 5 + 1))

        RESPONSE=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "{\"product_id\": \"${PRODUCT}\", \"quantity\": ${QUANTITY}}" \
            "${ORDER_API_URL}/orders")

        STATUS=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('order', {}).get('status', d.get('error', 'unknown')))" 2>/dev/null || echo "?")

        echo -e "  Orden ${i}: producto=${PRODUCT} qty=${QUANTITY} → ${STATUS}"
        sleep 0.3
    done

    echo ""
    echo -e "${GREEN}✅ ${count} órdenes procesadas${NC}"
}

# ── Función: Casuística 5 — Agotar Stock ─────────────────────────────────────
run_stock_drain() {
    echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  💥 CASUÍSTICA 5: AGOTANDO EL STOCK             ║${NC}"
    echo -e "${RED}║  Drenando el inventario de headset-01            ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}👁️  OBSERVA EN GRAFANA:${NC}"
    echo "   Panel: '📊 Nivel de Stock por Producto'"
    echo "   Barra de 'Headset Gaming' bajará hasta 0"
    echo "   Alerta 'LowInventoryStock' → 'ZeroInventoryStock' disparará"
    echo ""

    read -p "Presiona ENTER para iniciar... " -r

    # headset-01 tiene solo 10 unidades — lo agotamos rápido
    for i in $(seq 1 12); do
        RESPONSE=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -d '{"product_id": "headset-01", "quantity": 1}' \
            "${ORDER_API_URL}/orders")

        STATUS=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('order',{}).get('status', d.get('error','?')))" 2>/dev/null || echo "?")
        echo -e "  Intento ${i}: ${STATUS}"
        sleep 1
    done

    echo ""
    echo -e "${GREEN}✅ Demo completada. Verifica la alerta en Grafana/Prometheus.${NC}"
    echo -e "${CYAN}Para reponer stock: curl -X POST ${INVENTORY_URL}/inventory/headset-01/restock -d '{\"quantity\":50}' -H 'Content-Type: application/json'${NC}"
}

# ── Menú Principal ────────────────────────────────────────────────────────────
show_menu() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   🧪 SCRIPTS DE CASUÍSTICAS — Taller K8s              ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  URLs del entorno:"
    echo -e "  📦 order-api:         ${CYAN}${ORDER_API_URL}${NC}"
    echo -e "  🏭 inventory-service: ${CYAN}${INVENTORY_URL}${NC}"
    echo ""
    echo "  Opciones disponibles:"
    echo "  [memory]  Casuística 2: Memory Leak"
    echo "  [load]    Casuística 3: Tormenta de Requests (activa HPA)"
    echo "  [drain]   Casuística 5: Agotar Stock de inventario"
    echo "  [orders]  Crear órdenes reales para tráfico normal"
    echo ""
    echo "  Uso: bash load-testing/stress-test.sh <opción> [iteraciones]"
    echo ""
}

# ── Entry Point ───────────────────────────────────────────────────────────────
COMMAND=${1:-"menu"}
ITERATIONS=${2:-50}

case "$COMMAND" in
    "memory")  run_memory_leak "$ITERATIONS" ;;
    "load")    run_load_storm "$ITERATIONS" ;;
    "orders")  run_orders "$ITERATIONS" ;;
    "drain")   run_stock_drain ;;
    *)         show_menu ;;
esac

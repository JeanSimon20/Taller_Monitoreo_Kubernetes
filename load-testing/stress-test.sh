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

    # NOTA: Cada llamada acumula 1KB. Para ver el efecto en Grafana:
    #   80 iter  → 80KB  (invisible, < 0.1% del límite de 256MB)
    #   5000 iter → 5MB  (visible en el gauge memory_leak_simulation_bytes)
    #   100000 iter → ~100MB (dispara la alerta HighMemoryUsage al 85% de 256MB)
    if (( iterations < 1000 )); then
        echo -e "${YELLOW}⚠️  AVISO: ${iterations} iteraciones = solo $((iterations))KB acumulados.${NC}"
        echo -e "${YELLOW}   Recomendado: al menos 5000 para que Grafana lo muestre visualmente.${NC}"
        echo -e "${YELLOW}   Usa: bash load-testing/stress-test.sh memory 5000${NC}"
        echo ""
    fi

    for i in $(seq 1 "$iterations"); do
        RESPONSE=$(curl -s -w " | HTTP:%{http_code}" "${ORDER_API_URL}/orders/stress")
        # Mostrar progreso cada 100 llamadas para no saturar la terminal
        if (( i % 100 == 0 )) || (( i <= 10 )); then
            MEM_KB=$(echo "$RESPONSE" | grep -o '"memory_used_kb": [0-9.]*' | grep -o '[0-9.]*' 2>/dev/null || echo "?")
            echo -e "  [${i}/${iterations}] Memoria acumulada: ~${MEM_KB} KB"
        fi
        sleep 0.1   # Reducido de 0.5s a 0.1s — más rápido
    done

    TOTAL_KB=$(( iterations ))
    echo ""
    echo -e "${GREEN}✅ Memory leak simulado: ~${TOTAL_KB}KB acumulados. Verifica en Grafana.${NC}"
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
    echo -e "${YELLOW}  (Las oleadas son continuas, sin pausa — esto sí dispara la CPU)${NC}"
    echo ""

    local WAVE_SIZE=50   # 50 requests simultáneos en cada oleada — satura la CPU
    local sent=0

    while (( sent < iterations )); do
        # Calcular cuántos lanzar en esta oleada
        local this_wave=$WAVE_SIZE
        if (( sent + this_wave > iterations )); then
            this_wave=$(( iterations - sent ))
        fi

        # Lanzar oleada de requests todos en background (sin wait entre ellos)
        for j in $(seq 1 "$this_wave"); do
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
        done

        sent=$(( sent + this_wave ))
        # Espera que termine esta oleada antes de disparar la siguiente
        wait
        echo " [$sent/$iterations] — $(date +%H:%M:%S)"
        # Sin sleep: oleadas continuas para mantener presión de CPU sostenida
    done

    echo ""
    echo ""
    echo -e "${GREEN}✅ Tormenta completada. Observa cómo el HPA reduce los pods en ~5 minutos.${NC}"
    echo -e "${CYAN}   kubectl get hpa -n taller-monitoreo --watch${NC}"
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

    # PASO 0: Reponer stock primero para garantizar que la demo funcione siempre
    echo -e "${CYAN}[SETUP] Reponiendo stock de headset-01 a 15 unidades para la demo...${NC}"
    RESTOCK=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d '{"quantity": 15}' \
        "${INVENTORY_URL}/inventory/headset-01/restock" 2>/dev/null || echo '{}')
    NEW_STOCK=$(echo "$RESTOCK" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('new_stock','?'))" 2>/dev/null || echo "?")
    echo -e "${GREEN}  ✅ Stock de headset-01 → ${NEW_STOCK} unidades${NC}"
    echo ""

    read -p "Presiona ENTER para iniciar el drenado... " -r

    # Agotar las 15 unidades de a 1 — veremos la barra bajar en Grafana
    for i in $(seq 1 18); do
        RESPONSE=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -d '{"product_id": "headset-01", "quantity": 1}' \
            "${ORDER_API_URL}/orders")

        STATUS=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('order',{}).get('status', d.get('error','?')))" 2>/dev/null || echo "?")
        STOCK=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('order',{}).get('remaining_stock',''))" 2>/dev/null || echo "")
        STOCK_MSG=""
        [ -n "$STOCK" ] && STOCK_MSG=" (stock restante: ${STOCK})"
        echo -e "  Intento ${i}: ${STATUS}${STOCK_MSG}"
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

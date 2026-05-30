"""
=============================================================================
ORDER-API — Microservicio de Órdenes de Compra
=============================================================================
PROFESOR DICE:
  Este servicio expone métricas Prometheus de forma NATIVA.
  Fíjate en estas cuatro categorías de métricas que vamos a ver en clase:

  1. COUNTER   → Solo sube, nunca baja (ej: total de órdenes)
  2. GAUGE     → Puede subir y bajar (ej: órdenes en proceso)
  3. HISTOGRAM → Distribución de valores (ej: latencia de requests)
  4. SUMMARY   → Similar al histogram pero calcula percentiles en el cliente

  Cada vez que agregas una métrica, te preguntas:
  "¿Qué pregunta de negocio resuelve esto?"
=============================================================================
"""

import os
import time
import uuid
import random
import logging
import requests

from flask import Flask, request, jsonify
from prometheus_client import (
    Counter, Gauge, Histogram, Summary,
    generate_latest, CONTENT_TYPE_LATEST
)

# ─── Configuración ───────────────────────────────────────────────────────────
app = Flask(__name__)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)

# URL del servicio de inventario (se configura via variable de entorno)
INVENTORY_URL = os.getenv("INVENTORY_SERVICE_URL", "http://inventory-service:3000")

# Base de datos en memoria (para el taller — sin persistencia)
orders_db = []

# ─── Definición de Métricas Prometheus ───────────────────────────────────────
# PROFESOR DICE: Las métricas se definen UNA VEZ al inicio del programa.
# Los "labels" (etiquetas) permiten filtrar datos en las queries de PromQL.

# Counter: Total de órdenes creadas, segmentado por estado
orders_total = Counter(
    "orders_total",
    "Total de órdenes procesadas",
    ["status"]  # label: 'success' o 'failed'
)

# Gauge: Órdenes actualmente en estado "pending"
orders_pending = Gauge(
    "orders_pending_total",
    "Número de órdenes pendientes de proceso"
)

# Histogram: Latencia de cada request HTTP
# PROFESOR DICE: Los 'buckets' definen los rangos de tiempo que queremos medir.
# Aquí medimos tiempos entre 10ms y 10 segundos.
http_request_duration = Histogram(
    "http_request_duration_seconds",
    "Duración de los requests HTTP en segundos",
    ["method", "endpoint", "status_code"],
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
)

# Counter: Llamadas al inventory-service
inventory_calls = Counter(
    "inventory_service_calls_total",
    "Total de llamadas realizadas al inventory-service",
    ["status"]  # 'success', 'timeout', 'error'
)

# Gauge: Simula uso de memoria (para la Casuística 2 - Memory Leak)
# PROFESOR DICE: Esta lista se llena intencionalmente en el endpoint /stress
memory_leak_simulation = []
memory_leak_gauge = Gauge(
    "memory_leak_simulation_bytes",
    "Simulación de fuga de memoria (bytes usados en lista interna)"
)


# ─── Decorador para medir latencia automáticamente ───────────────────────────
# PROFESOR DICE: Este patrón es muy común en producción. Envuelves tus
# endpoints con un decorator que mide el tiempo automáticamente.
def track_request_metrics(endpoint_name):
    def decorator(f):
        def wrapper(*args, **kwargs):
            start_time = time.time()
            status_code = 500
            try:
                response = f(*args, **kwargs)
                status_code = response[1] if isinstance(response, tuple) else 200
                return response
            except Exception as e:
                status_code = 500
                raise e
            finally:
                duration = time.time() - start_time
                http_request_duration.labels(
                    method=request.method,
                    endpoint=endpoint_name,
                    status_code=str(status_code)
                ).observe(duration)
        wrapper.__name__ = f.__name__
        return wrapper
    return decorator


# ─── Endpoints ───────────────────────────────────────────────────────────────

@app.route("/health")
def health():
    """
    PROFESOR DICE: El health check es FUNDAMENTAL en Kubernetes.
    El kubelet lo usa para determinar si el pod está vivo (liveness)
    y si está listo para recibir tráfico (readiness).
    Siempre responde rápido y sin dependencias externas.
    """
    return jsonify({
        "status": "healthy",
        "service": "order-api",
        "version": "1.0.0",
        "timestamp": time.time()
    }), 200


@app.route("/metrics")
def metrics():
    """
    PROFESOR DICE: Este endpoint es el que Prometheus hace 'scrape'.
    Prometheus viene cada 15 segundos y pide esta URL.
    La librería prometheus_client genera el formato correcto automáticamente.
    """
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


@app.route("/orders", methods=["GET"])
@track_request_metrics("/orders")
def list_orders():
    """Lista todas las órdenes almacenadas en memoria."""
    logger.info(f"Listando {len(orders_db)} órdenes")
    return jsonify({
        "orders": orders_db,
        "total": len(orders_db)
    }), 200


@app.route("/orders", methods=["POST"])
@track_request_metrics("/orders")
def create_order():
    """
    Crea una nueva orden. Internamente llama al inventory-service
    para verificar y reservar el stock del producto.

    PROFESOR DICE: Este flujo nos permite ver en Grafana cómo
    la latencia de inventory-service afecta a order-api.
    """
    data = request.get_json()
    if not data or "product_id" not in data or "quantity" not in data:
        orders_total.labels(status="failed").inc()
        return jsonify({"error": "Se requieren 'product_id' y 'quantity'"}), 400

    order_id = str(uuid.uuid4())[:8]
    product_id = data["product_id"]
    quantity = int(data["quantity"])

    logger.info(f"Creando orden {order_id} para producto {product_id} x{quantity}")
    orders_pending.inc()  # Marcamos la orden como pendiente

    # Llamada al inventory-service
    inventory_status = _call_inventory(product_id, quantity)

    if inventory_status == "success":
        order = {
            "id": order_id,
            "product_id": product_id,
            "quantity": quantity,
            "status": "confirmed",
            "created_at": time.time()
        }
        orders_db.append(order)
        orders_total.labels(status="success").inc()
        orders_pending.dec()
        logger.info(f"Orden {order_id} confirmada exitosamente")
        return jsonify({"order": order, "message": "Orden creada exitosamente"}), 201

    elif inventory_status == "insufficient_stock":
        orders_total.labels(status="failed").inc()
        orders_pending.dec()
        return jsonify({"error": "Stock insuficiente para el producto", "product_id": product_id}), 409

    else:
        orders_total.labels(status="failed").inc()
        orders_pending.dec()
        return jsonify({"error": f"Error al contactar inventory-service: {inventory_status}"}), 503


@app.route("/orders/stress", methods=["GET"])
def stress_endpoint():
    """
    ==========================================================================
    CASUÍSTICA 2 — FUGA DE MEMORIA (Memory Leak)
    ==========================================================================
    PROFESOR DICE: Este endpoint INTENCIONALMENTE acumula datos en memoria.
    En producción, esto ocurre cuando:
    - Se cachean objetos sin límite
    - Se guardan referencias que nunca se liberan
    - Se acumulan conexiones de base de datos

    Ejecuta este endpoint varias veces y observa en Grafana cómo el gauge
    'memory_leak_simulation_bytes' sube sin parar.
    Comando: for i in {1..50}; do curl http://<URL>/orders/stress; done
    ==========================================================================
    """
    # Acumulamos 1KB de datos en cada llamada — esto es el leak intencional
    chunk_size = 1024  # 1 KB
    memory_leak_simulation.append("X" * chunk_size)

    current_size = len(memory_leak_simulation) * chunk_size
    memory_leak_gauge.set(current_size)

    logger.warning(f"[STRESS] Memoria acumulada: {current_size / 1024:.2f} KB — CASUÍSTICA 2 ACTIVA")

    return jsonify({
        "message": "Endpoint de stress - Casuística 2: Memory Leak",
        "memory_used_kb": current_size / 1024,
        "items_in_memory": len(memory_leak_simulation),
        "warning": "Este endpoint acumula memoria intencionalmente para la demo"
    }), 200


@app.route("/orders/reset-stress", methods=["POST"])
def reset_stress():
    """Limpia la memoria acumulada por /stress. Úsalo después de la casuística."""
    global memory_leak_simulation
    memory_leak_simulation = []
    memory_leak_gauge.set(0)
    logger.info("Memoria de stress liberada")
    return jsonify({"message": "Memoria liberada correctamente"}), 200


# ─── Función auxiliar: llamada al inventory-service ──────────────────────────
def _call_inventory(product_id: str, quantity: int) -> str:
    """
    Llama al inventory-service para reservar stock.
    Retorna: 'success', 'insufficient_stock', 'timeout', 'error'

    PROFESOR DICE: Aquí es donde medimos la salud de la comunicación
    entre microservicios. Si inventory-service está lento o caído,
    estas métricas lo mostrarán ANTES de que los usuarios se queden.
    """
    try:
        url = f"{INVENTORY_URL}/inventory/{product_id}/reserve"
        start = time.time()

        response = requests.post(
            url,
            json={"quantity": quantity},
            timeout=3.0  # 3 segundos de timeout
        )

        elapsed = time.time() - start
        logger.info(f"Llamada a inventory-service: {elapsed:.3f}s, status={response.status_code}")

        if response.status_code == 200:
            inventory_calls.labels(status="success").inc()
            return "success"
        elif response.status_code == 409:
            inventory_calls.labels(status="success").inc()
            return "insufficient_stock"
        else:
            inventory_calls.labels(status="error").inc()
            return "error"

    except requests.exceptions.Timeout:
        logger.error(f"TIMEOUT contactando inventory-service para producto {product_id}")
        inventory_calls.labels(status="timeout").inc()
        return "timeout"

    except requests.exceptions.ConnectionError:
        logger.error(f"No se puede conectar a inventory-service: {INVENTORY_URL}")
        inventory_calls.labels(status="error").inc()
        return "error"


# ─── Entry Point ─────────────────────────────────────────────────────────────
if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    logger.info(f"order-api iniciando en puerto {port}")
    logger.info(f"inventory-service URL: {INVENTORY_URL}")
    app.run(host="0.0.0.0", port=port, debug=False)

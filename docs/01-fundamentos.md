# 📖 Módulo 1 — Fundamentos de Observabilidad

## ¿Por qué necesitamos monitoreo?

Imagina que tienes una caja negra. Entra tráfico, salen respuestas.
¿Cómo sabes si está funcionando bien? ¿Si está a punto de fallar?
**Esa caja negra es tu aplicación en producción.**

La observabilidad nos da "ventanas" a esa caja negra.

---

## Los 3 Pilares de la Observabilidad

```
┌────────────────────────────────────────────────────────┐
│                  OBSERVABILIDAD                        │
│                                                        │
│   📊 MÉTRICAS   📋 LOGS      🔍 TRAZAS               │
│   (¿Cuánto?)    (¿Qué pasó?) (¿Por dónde fue?)       │
│                                                        │
│   Prometheus    Loki/ELK    Jaeger/Zipkin             │
│   Grafana       Kibana       Tempo                    │
└────────────────────────────────────────────────────────┘
```

### 📊 Métricas (Prometheus)
- Datos numéricos en el tiempo
- "¿Cuántas órdenes por minuto?" / "¿CPU al 80%?"
- Perfectas para alertas y dashboards
- **Lo que hacemos en este taller**

### 📋 Logs (fuera del alcance de este taller)
- Registros de eventos con timestamp
- "¿Qué error exacto ocurrió?"
- Perfectos para debugging detallado

### 🔍 Trazas (fuera del alcance)
- El "camino" de un request a través de múltiples servicios
- "¿En qué servicio exactamente está la lentitud?"
- Perfectas para arquitecturas de microservicios complejas

---

## Los 4 Tipos de Métricas en Prometheus

### 1. Counter (Contador)
**Definición**: Solo sube, nunca baja. Se reinicia cuando el proceso reinicia.

```python
# Python
orders_total = Counter("orders_total", "Total de órdenes", ["status"])
orders_total.labels(status="success").inc()  # +1
```

**Cuándo usarlo**: Total de requests, total de errores, total de bytes procesados.

**Query PromQL**: `rate(orders_total[5m])` — tasa de cambio en 5 minutos.

### 2. Gauge (Indicador)
**Definición**: Puede subir y bajar. Representa un valor actual.

```python
# Python
stock_level = Gauge("stock_level", "Stock actual", ["product"])
stock_level.labels(product="laptop").set(42)   # fijar a 42
stock_level.labels(product="laptop").dec()      # bajar 1
```

**Cuándo usarlo**: Temperatura, stock, usuarios conectados, uso de memoria.

**Query PromQL**: `inventory_stock_level < 5` — alertas directas.

### 3. Histogram (Histograma)
**Definición**: Cuenta valores en rangos (buckets). Permite calcular percentiles.

```python
# Python
latency = Histogram("request_seconds", "Latencia", buckets=[0.1, 0.5, 1, 2, 5])
with latency.time():  # mide automáticamente el tiempo
    procesar_orden()
```

**Cuándo usarlo**: Latencia de requests, tamaño de archivos, duración de queries.

**Query PromQL**: `histogram_quantile(0.95, rate(request_seconds_bucket[5m]))` — p95.

### 4. Summary (Resumen)
**Definición**: Similar al histogram, pero calcula percentiles en el cliente.
Menos flexible que el histogram para queries. Preferimos Histogram en la práctica.

---

## Por Qué Kubernetes Necesita Monitoreo Especial

En un servidor tradicional:
```
Un servidor → monitorear 1 IP
```

En Kubernetes:
```
Muchos pods → IPs que cambian → pods que escalan y se destruyen
```

**El problema**: Si un pod muere y nace uno nuevo, tiene una IP diferente.
Prometheus no puede tener una lista estática de IPs.

**La solución**: Service Discovery — Prometheus pregunta a Kubernetes
"¿Qué pods tienen el label `monitoring: enabled`?" y obtiene la lista dinámicamente.

---

## El Ciclo de Observabilidad

```
SISTEMA ──► MÉTRICAS ──► PROMETHEUS ──► GRAFANA ──► ALERTA
  │              │            │              │           │
  │         /metrics       scrape        dashboard    pagerduty
  │         endpoint       cada 15s      panels       slack
  │                                                     │
  └─────────────────────── acción ◄────────────────────┘
```

---

## Checkpoint del Módulo 1 ✅

Antes de continuar, verifica que entiendes:
- [ ] ¿Cuál es la diferencia entre un Counter y un Gauge?
- [ ] ¿Por qué usamos Histogram en lugar de guardar todos los valores de latencia?
- [ ] ¿Por qué Prometheus necesita Service Discovery en Kubernetes?

**Comando de verificación**:
```bash
# Debería mostrar las métricas de los servicios del taller
curl http://$(minikube ip):30500/metrics | head -30
```

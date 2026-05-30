# 📖 Módulo 5 — Las 5 Casuísticas del Taller

> **Esta es la parte más importante del taller.**
> Vamos a reproducir situaciones reales de producción, en un entorno controlado,
> y aprender a diagnosticarlas con Prometheus y Grafana.

---

## Cómo funciona cada casuística

Cada casuística sigue el mismo formato:

1. **🎬 Contexto narrativo** — "Es lunes a las 9am, el negocio abre..."
2. **😱 Síntoma** — Lo que el usuario final experimenta
3. **🔍 Diagnóstico** — Cómo lo detectamos en Grafana/Prometheus
4. **🔧 Solución** — El comando exacto para arreglarlo
5. **📚 Lección** — El concepto de Kubernetes que aprendemos

---

## 💀 Casuística 1: "El Servicio Muerto"

### 🎬 Contexto
"Son las 8am del lunes. El equipo de DevOps actualizó la configuración de order-api
el domingo por la noche. Pero cometieron un error: pusieron mal el nombre de una
variable de entorno. Los usuarios no pueden hacer órdenes."

### 😱 Síntoma del Usuario Final
- Las solicitudes a `/orders` retornan error 503
- El app móvil muestra "Servicio no disponible"

### 🔍 Diagnóstico en Grafana/Prometheus

**Panel que observar**: `🟢 Estado order-api` → cambia a ❌

**En Prometheus** (http://localhost:9090):
```promql
# El target aparece como 0 (DOWN)
up{job="order-api"}

# Los pods en CrashLoopBackOff
kube_pod_container_status_waiting_reason{
  reason="CrashLoopBackOff",
  namespace="taller-monitoreo"
}
```

**En kubectl**:
```bash
kubectl get pods -n taller-monitoreo
# NAME                         READY   STATUS             RESTARTS   AGE
# order-api-xxx-yyy            0/1     CrashLoopBackOff   5          3m

kubectl logs order-api-xxx-yyy -n taller-monitoreo --previous
# Error: INVENTORY_SERVICE_URL environment variable not set correctly
```

### 🎮 Cómo Activarla (Demo en Vivo)

**PASO 1**: Romper el deployment
```bash
# Ponemos una variable de entorno incorrecta
kubectl set env deployment/order-api \
  INVENTORY_SERVICE_URL="http://wrong-url:9999" \
  -n taller-monitoreo

# Observar cómo falla
kubectl get pods -n taller-monitoreo --watch
```

**PASO 2**: Ver la alerta en Grafana
- Ir al panel `🟢 Estado order-api` → se vuelve rojo
- Ir a Alertas → `OrderApiDown` en estado FIRING

**PASO 3**: Arreglarlo
```bash
kubectl set env deployment/order-api \
  INVENTORY_SERVICE_URL="http://inventory-service.taller-monitoreo.svc.cluster.local:3000" \
  -n taller-monitoreo

kubectl rollout status deployment/order-api -n taller-monitoreo
```

### 📚 Lección: Liveness vs Readiness Probes

```yaml
# Liveness Probe: ¿Está vivo el proceso?
# → Si falla N veces, Kubernetes MATA y reinicia el pod
livenessProbe:
  httpGet:
    path: /health
    port: 5000
  failureThreshold: 3

# Readiness Probe: ¿Está listo para tráfico?
# → Si falla, el pod sale del balanceador (sin matar el proceso)
readinessProbe:
  httpGet:
    path: /health
    port: 5000
  failureThreshold: 3
```

**Pregunta para el grupo**: ¿Por qué tener dos probes distintos en lugar de uno?

---

## 🧠 Casuística 2: "La Fuga de Memoria"

### 🎬 Contexto
"order-api tiene un endpoint `/orders/stress` que los developers usaron para pruebas
de carga. Olvidaron una lista global que nunca se vacía. Cada request acumula 1KB
en memoria. Con 50 requests por minuto en producción, en 4 horas el pod es
matado por el OOMKiller de Linux."

### 😱 Síntoma del Usuario Final
- El servicio reinicia misteriosamente cada pocas horas
- Los logs muestran: `OOMKilled`

### 🔍 Diagnóstico en Grafana

**Panel que observar**: `🧠 Uso de Memoria — Casuística 2: Memory Leak`

**Query PromQL**:
```promql
# Memoria en uso (working set) del contenedor order-api
container_memory_working_set_bytes{
  namespace="taller-monitoreo",
  container="order-api"
}

# Nuestra métrica de simulación
memory_leak_simulation_bytes

# Porcentaje del límite de memoria usado
container_memory_working_set_bytes{container="order-api"}
/
kube_pod_container_resource_limits{resource="memory", container="order-api"}
```

### 🎮 Cómo Activarla

```bash
# Activar el leak (llama a /orders/stress 100 veces)
bash load-testing/stress-test.sh memory 100

# Observar en tiempo real:
watch -n 3 "curl -s http://$(minikube ip):30500/metrics | grep memory_leak"
```

**En Grafana**: La alerta `HighMemoryUsage` debería disparar cuando supere el 85% del límite.

### 🔧 Solución

```bash
# Limpiar el leak (endpoint de reset)
curl -X POST http://$(minikube ip):30500/orders/reset-stress

# En producción: restart del pod (solución de emergencia)
kubectl rollout restart deployment/order-api -n taller-monitoreo
```

### 📚 Lección: Resource Limits como Protección

```yaml
resources:
  requests:
    memory: "128Mi"   # K8s garantiza este mínimo al pod
  limits:
    memory: "256Mi"   # Si supera esto → OOMKill → pod se reinicia
```

**Lección clave**: Los limits NO son restricciones arbitrarias. Son la primera
línea de defensa contra que un pod con leak destruya el nodo entero.

---

## 🌊 Casuística 3: "La Tormenta de Requests"

### 🎬 Contexto
"El equipo de marketing lanzó una campaña sin avisar al equipo de tech.
En 5 minutos, el tráfico a order-api aumentó 10x. El sistema empieza a
responder lento y algunos requests se pierden."

### 😱 Síntoma del Usuario Final
- La app tarda mucho en responder
- Algunos requests retornan 500 o timeout

### 🔍 Diagnóstico en Grafana

**Panels que observar**:
- `⚡ Uso de CPU` → sube a 90%+
- `⏱️ Latencia HTTP — p50, p95, p99` → p99 sube a varios segundos
- `🔢 Pods Running — order-api (HPA)` → sube de 1 a 3 pods automáticamente

**Queries PromQL**:
```promql
# Tasa de requests por minuto
rate(http_request_duration_seconds_count[1m]) * 60

# Latencia p95
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# CPU actual vs límite
rate(container_cpu_usage_seconds_total{container="order-api"}[2m])
```

### 🎮 Cómo Activarla

**Terminal 1** — Lanzar la tormenta:
```bash
bash load-testing/stress-test.sh load 500
```

**Terminal 2** — Ver el HPA escalando:
```bash
kubectl get hpa -n taller-monitoreo --watch
# NAME            REFERENCE              TARGETS   MINPODS   MAXPODS   REPLICAS
# order-api-hpa   Deployment/order-api   85%/70%   1         5         1
# order-api-hpa   Deployment/order-api   85%/70%   1         5         3   ← ESCALÓ!
```

### 🔧 Cómo Funciona el HPA

```bash
# Ver detalles del HPA
kubectl describe hpa order-api-hpa -n taller-monitoreo

# El HPA usa el metrics-server para obtener CPU actual:
kubectl top pods -n taller-monitoreo
```

### 📚 Lección: Horizontal Pod Autoscaler

El HPA monitorea métricas del cluster y ajusta réplicas automáticamente:

```yaml
# Si CPU > 70% durante 30s → agrega pods (hasta 5)
# Si CPU < 70% durante 5min → reduce pods (hasta 1)
metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

**Pregunta para el grupo**: ¿Por qué el HPA tarda más en bajar pods que en subirlos?

---

## 🐌 Casuística 4: "El Servicio Lento"

### 🎬 Contexto
"inventory-service fue actualizado y tiene una query a base de datos muy lenta
(no estaba optimizada). order-api tiene un timeout de 3 segundos. Cuando
inventory-service tarda más de 3s, order-api reporta el error al usuario."

### 😱 Síntoma del Usuario Final
- Las órdenes fallan con "Error al contactar inventory-service: timeout"
- Solo afecta la CREACIÓN de órdenes (no la consulta)

### 🔍 Diagnóstico en Grafana

**Panels que observar**:
- `⏱️ Latencia de Reservas — inventory-service` → sube drásticamente
- `⚠️ Timeouts Inventario` → contador crece
- Alerta `InventoryServiceTimeouts` → FIRING

**Queries PromQL**:
```promql
# Tasa de timeouts al llamar inventory-service
rate(inventory_service_calls_total{status="timeout"}[5m])

# Latencia p95 de las reservas
histogram_quantile(0.95,
  rate(inventory_reservation_duration_seconds_bucket[5m])
)

# Ver el delay de chaos configurado
inventory_chaos_delay_ms
```

### 🎮 Cómo Activarla

**Terminal 1** — Activar el delay:
```bash
bash load-testing/chaos-delay.sh enable 2000  # 2 segundos de delay
```

**Terminal 2** — Generar tráfico con órdenes:
```bash
for i in {1..20}; do
  curl -s -X POST http://$(minikube ip):30500/orders \
    -H "Content-Type: application/json" \
    -d '{"product_id": "laptop-01", "quantity": 1}'
  echo ""
  sleep 1
done
```

**Terminal 3** — Observar los timeouts:
```bash
watch -n 2 "curl -s http://$(minikube ip):30500/metrics | grep inventory_service_calls"
```

### 🔧 Solución

```bash
# Opción 1: Arreglar el servicio lento (quitar el delay)
bash load-testing/chaos-delay.sh disable

# Opción 2: Aumentar el timeout de order-api (parche temporal)
# En app.py: timeout=3.0 → timeout=10.0 + kubectl rollout restart
```

### 📚 Lección: Resiliencia entre Microservicios

**Circuit Breaker Pattern**: Si un servicio falla repetidamente, "cortamos el circuito"
y retornamos error inmediato en lugar de esperar el timeout.

```python
# En order-api, si inventory falla más de 5 veces en 1 minuto,
# retornamos "inventory unavailable" inmediatamente durante 30s
# En lugar de hacer el alumno esperar 3s por request
```

**Diseño para fallos**: Todo microservicio DEBE asumir que sus dependencias fallarán.

---

## 📦 Casuística 5: "El Stock Cero"

### 🎬 Contexto
"El headset gaming es el producto más popular. Hay solo 10 unidades.
Un bot de compra (o simplemente mucho tráfico orgánico) agota el stock
en minutos. El equipo de operaciones no se entera hasta que los clientes
se quejan en redes sociales."

### 😱 Síntoma del Usuario Final
- Las órdenes de headset-01 retornan "Stock insuficiente"
- El equipo de ventas no sabe que se agotó el stock

### 🔍 Diagnóstico en Grafana

**Panel que observar**: `📊 Nivel de Stock por Producto (Casuística 5)`
- La barra de "Headset Gaming" baja progresivamente hasta ROJO (< 5 unidades)
- Cuando llega a 0, la barra desaparece del gráfico

**Alertas que disparan**:
1. `LowInventoryStock` → cuando stock < 5 (SEVERITY: warning)
2. `ZeroInventoryStock` → cuando stock == 0 (SEVERITY: critical)

**Queries PromQL**:
```promql
# Stock actual de todos los productos
inventory_stock_level

# Solo productos en bajo stock
inventory_stock_level < 5

# Alertas de bajo stock disparadas (acumulado)
inventory_low_stock_alerts_total
```

### 🎮 Cómo Activarla

```bash
bash load-testing/stress-test.sh drain
```

**Observar en Grafana**: El gauge de Headset Gaming baja a 0 en tiempo real.

### 🔧 Reponer el Stock

```bash
# Reponer inventario del headset
curl -X POST http://$(minikube ip):30300/inventory/headset-01/restock \
  -H "Content-Type: application/json" \
  -d '{"quantity": 50}'
```

### 📚 Lección: Métricas de Negocio vs Infraestructura

| Tipo | Métrica | ¿Quién la entiende? |
|---|---|---|
| Infraestructura | CPU 80% | Solo el equipo técnico |
| **Negocio** | **Stock de laptop: 0 unidades** | **Todos: tech, ventas, dirección** |

**La lección más importante del taller**: Un SRE moderno no solo monitorea servidores.
Monitorea el negocio. Una alerta de "stock agotado" puede valer más que todas las
alertas de CPU juntas.

---

## 📊 Resumen de PromQL del Taller

Estas son las queries más importantes que usamos durante el taller:

```promql
# ¿Están los servicios UP?
up{namespace="taller-monitoreo"}

# Tasa de éxito de órdenes (últimos 5 minutos)
rate(orders_total{status="success"}[5m])

# Latencia p95 de order-api
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Uso de CPU de los microservicios
rate(container_cpu_usage_seconds_total{namespace="taller-monitoreo"}[2m])

# Memoria usada vs límite (porcentaje)
container_memory_working_set_bytes{namespace="taller-monitoreo"}
/ kube_pod_container_resource_limits{resource="memory", namespace="taller-monitoreo"}

# Stock de inventario
inventory_stock_level

# Timeouts con inventory-service
rate(inventory_service_calls_total{status="timeout"}[5m])
```

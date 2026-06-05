# 🎓 Guía Completa — Taller de Monitoreo Kubernetes

> **Objetivo del taller**: Entender cómo se monitorea un sistema de microservicios
> en Kubernetes usando Prometheus y Grafana, reproduciendo problemas reales de producción.

---

## PARTE 1 — El Problema que Resuelven Prometheus y Grafana

### El mundo antes del monitoreo moderno

Imagina que eres responsable de una tienda online. Lunes 9am, los clientes llaman:
"No puedo completar mi compra". Tú abres tu laptop y... ¿qué haces?

Sin monitoreo: abres los logs línea por línea, corres por el servidor, revisas manualmente.
Puedes tardar **horas** en encontrar el problema.

Con monitoreo: abres Grafana, ves un dashboard, en **30 segundos** identificas que
`inventory-service` tiene latencia de 5 segundos y está causando timeouts en `order-api`.

**Eso es exactamente lo que hacemos en este taller.**

---

## PARTE 2 — ¿Qué es Prometheus?

### Definición

**Prometheus** es una base de datos de series de tiempo (Time Series Database, TSDB)
open source, creada por SoundCloud en 2012 y ahora parte de la CNCF.

Almacena datos en el formato:

```
nombre_metrica{label1="valor1", label2="valor2"}  valor  timestamp
orders_total{status="success"}                     142    1717618200
orders_total{status="failed"}                      7      1717618200
```

### ¿Cómo obtiene los datos? — El modelo PULL

La diferencia clave de Prometheus vs otros sistemas de monitoreo:

```
  PUSH (CloudWatch, StatsD):          PULL (Prometheus):
  
  App ──────► Monitor                  Prometheus ──► GET /metrics ──► App
  
  Problema: si la app muere,           Ventaja: si la app muere,
  deja de enviar datos y el            Prometheus detecta el fallo
  monitor no sabe si está muerta       inmediatamente (no recibe respuesta)
  o simplemente sin tráfico.
```

Prometheus viene cada 15 segundos a pedirle a cada servicio sus métricas.
Si el servicio no responde → alerta "servicio caído".

### ¿Qué tiene que hacer tu aplicación?

Solo exponer un endpoint HTTP `GET /metrics` con este formato:

```
# HELP orders_total Total de órdenes procesadas
# TYPE orders_total counter
orders_total{status="success"} 142.0
orders_total{status="failed"} 7.0
```

Eso es todo. El resto lo hace Prometheus.

### Los 4 tipos de métricas

| Tipo | Comportamiento | Ejemplo de uso | Query PromQL |
|---|---|---|---|
| **Counter** | Solo sube, nunca baja | Total de órdenes, total de errores | `rate(orders_total[5m])` |
| **Gauge** | Sube y baja | Stock en inventario, usuarios activos | `inventory_stock_level < 5` |
| **Histogram** | Distribución en rangos (buckets) | Latencia de requests, tamaño de archivos | `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))` |
| **Summary** | Como Histogram pero calcula percentiles en el cliente | Poco usado en práctica moderna | — |

**Regla de oro para elegir el tipo:**
- ¿El valor solo crece? → **Counter**
- ¿El valor puede bajar? → **Gauge**
- ¿Quiero calcular percentiles (p50, p95, p99)? → **Histogram**

---

## PARTE 3 — ¿Qué es Grafana?

### Definición

**Grafana** es una plataforma de visualización y análisis open source.
No almacena datos — los **lee** de fuentes de datos como Prometheus, MySQL, InfluxDB, etc.

```
Prometheus ──► almacena métricas ──► Grafana ──► muestra dashboards
                                         │
                                    también conecta a:
                                    - Loki (logs)
                                    - Tempo (trazas)
                                    - PostgreSQL
                                    - CloudWatch
                                    - y 100+ fuentes más
```

### ¿Qué puedes hacer en Grafana?

- **Dashboards**: Paneles con gráficos, tablas, gauges en tiempo real
- **Alertas**: Notificaciones por Slack, email, PagerDuty cuando algo supera un umbral
- **Anotaciones**: Marcar en el tiempo "aquí deployamos", "aquí corrimos el stress test"
- **Variables**: Dashboards dinámicos donde filtras por `namespace`, `pod`, `environment`

### Grafana en este taller

Accedes en: **http://localhost:3000** (admin / taller2024)

El dashboard del taller tiene 3 secciones:

```
🛒 ORDER-API — Métricas de Negocio
  ├── 📦 Total Órdenes
  ├── ❌ Órdenes Fallidas
  ├── ⏱️ Latencia p95
  ├── ⚠️ Timeouts Inventario
  ├── 🧠 Memory Leak (Casuística 2)
  ├── 📈 Tasa de Órdenes por Minuto
  └── ⏱️ Latencia HTTP — p50, p95, p99

📦 INVENTORY-SERVICE — Stock y Negocio
  ├── 📊 Nivel de Stock por Producto (Casuística 5)
  └── ⏱️ Latencia de Reservas (Casuística 4)

🖥️ INFRAESTRUCTURA — Pods y Recursos
  ├── 🧠 Uso de Memoria (Casuística 2)
  ├── ⚡ Uso de CPU (Casuística 3)
  ├── 🔢 Pods Running — order-api (HPA)
  ├── 💀 Pods en CrashLoopBackOff (Casuística 1)
  ├── 🟢 Estado order-api
  └── 🟢 Estado inventory-service
```

---

## PARTE 4 — La Relación Prometheus + Kubernetes

### El problema de Kubernetes vs monitoreo tradicional

En un servidor físico o VM:
```
Servidor A: IP 10.0.0.1 → siempre la misma
Servidor B: IP 10.0.0.2 → siempre la misma
```
Puedes configurar Prometheus con una lista estática de IPs.

En Kubernetes:
```
Pod de order-api se muere → K8s crea uno nuevo con IP 10.244.0.55
Pod se escala x3         → ahora hay 3 IPs distintas que cambian cada vez
```
No puedes usar una lista estática. Necesitas **Service Discovery**.

### Cómo Prometheus descubre servicios en Kubernetes

El **Prometheus Operator** instala un objeto nuevo en K8s llamado `ServiceMonitor`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: order-api-monitor
spec:
  selector:
    matchLabels:
      app: order-api        # ← "monitorea todos los Services con este label"
  endpoints:
    - port: http            # ← nombre del puerto en el Service
      path: /metrics        # ← ruta de métricas
      interval: 15s         # ← cada 15 segundos
```

El Prometheus Operator lee este objeto y **automáticamente** le dice a Prometheus
qué pods tiene que rastrear. Si hay 1 pod o 5, Prometheus los monitorea todos.

### Stack completo instalado en el taller

```
Helm chart: kube-prometheus-stack
│
├── Prometheus           → recolecta y almacena métricas
├── Grafana              → visualiza dashboards
├── AlertManager         → gestiona y enruta alertas
├── Prometheus Operator  → gestiona la configuración de Prometheus vía CRDs
├── kube-state-metrics   → métricas del estado de objetos K8s (pods, deployments...)
└── node-exporter        → métricas del servidor (CPU, RAM, disco del nodo)
```

Todos instalados con **un solo comando**:
```bash
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring
```

---

## PARTE 5 — Los Microservicios del Taller

### Arquitectura del sistema

```
                    ┌─────────────────────────────────────────┐
                    │         CLUSTER KUBERNETES              │
                    │  (namespace: taller-monitoreo)          │
                    │                                         │
  Cliente           │   ┌───────────────┐                     │
  (stress test) ────┼──►│   order-api   │                     │
                    │   │   Python/Flask│                     │
                    │   │   Puerto 5000 │                     │
                    │   └───────┬───────┘                     │
                    │           │ HTTP POST /reserve           │
                    │           ▼                              │
                    │   ┌───────────────────┐                 │
                    │   │ inventory-service │                 │
                    │   │   Node.js/Express │                 │
                    │   │   Puerto 3000     │                 │
                    │   └───────────────────┘                 │
                    │                                         │
                    │  (namespace: monitoring)                │
                    │   ┌──────────────┐  ┌──────────────┐  │
                    │   │  Prometheus  │  │   Grafana    │  │
                    │   │  Puerto 9090 │  │  Puerto 3000 │  │
                    │   └──────────────┘  └──────────────┘  │
                    └─────────────────────────────────────────┘
```

### Servicio 1: order-api (Python/Flask)

**¿Qué hace?** Es una API REST que recibe pedidos de compra.

**Endpoints:**
| Método | Ruta | Descripción |
|---|---|---|
| GET | `/health` | Health check para K8s (liveness/readiness probe) |
| GET | `/metrics` | Endpoint que Prometheus raspa cada 15s |
| GET | `/orders` | Lista todas las órdenes en memoria |
| POST | `/orders` | Crea una nueva orden (llama a inventory-service) |
| GET | `/orders/stress` | **Casuística 2**: acumula 1KB en memoria por llamada |
| POST | `/orders/reset-stress` | Limpia la memoria acumulada por /stress |

**Métricas que expone:**
```python
# Counter: total de órdenes, segmentado por resultado
orders_total{status="success"}   # órdenes exitosas
orders_total{status="failed"}    # órdenes fallidas

# Gauge: órdenes actualmente procesándose
orders_pending_total

# Histogram: latencia de cada request HTTP
http_request_duration_seconds{method="POST", endpoint="/orders", status_code="201"}

# Counter: llamadas al inventory-service y su resultado
inventory_service_calls_total{status="success"}
inventory_service_calls_total{status="timeout"}
inventory_service_calls_total{status="error"}

# Gauge: simulación de memory leak (Casuística 2)
memory_leak_simulation_bytes
```

**Configuración K8s relevante:**
```yaml
# Límite de memoria → si supera 256MB, OOMKiller lo mata (Casuística 2)
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"

# Timeout a inventory-service: 3 segundos (Casuística 4)
# Si inventory-service tarda más de 3s → timeout → orden fallida
```

### Servicio 2: inventory-service (Node.js/Express)

**¿Qué hace?** Gestiona el stock de productos. Verifica y descuenta inventario.

**Productos en stock:**
| ID | Nombre | Stock inicial |
|---|---|---|
| laptop-01 | Laptop Pro 15" | 50 |
| mouse-01 | Mouse Inalámbrico | 200 |
| kb-01 | Teclado Mecánico | 75 |
| monitor-01 | Monitor 4K 27" | 30 |
| **headset-01** | **Headset Gaming** | **10** ← stock bajo para la demo |

**Endpoints:**
| Método | Ruta | Descripción |
|---|---|---|
| GET | `/health` | Health check |
| GET | `/metrics` | Endpoint Prometheus |
| GET | `/inventory` | Lista todo el inventario |
| GET | `/inventory/:id` | Stock de un producto específico |
| POST | `/inventory/:id/reserve` | **Descuenta stock** (llamado por order-api) |
| POST | `/inventory/:id/restock` | Repone stock (para resetear demos) |

**Métricas que expone:**
```javascript
// Counter: total de requests HTTP
inventory_requests_total{method, endpoint, status_code}

// Gauge: stock actual de cada producto (se actualiza en tiempo real)
inventory_stock_level{product_id="laptop-01", product_name="Laptop Pro 15\""}
inventory_stock_level{product_id="headset-01", product_name="Headset Gaming"}

// Histogram: latencia de las operaciones de reserva
inventory_reservation_duration_seconds{product_id, result}

// Counter: alertas de bajo stock disparadas
inventory_low_stock_alerts_total{product_id}

// Gauge: delay de chaos configurado (Casuística 4)
inventory_chaos_delay_ms
```

**La variable mágica de Casuística 4:**
```bash
# Esta variable de entorno inyecta un delay artificial en cada reserva
CHAOS_DELAY_MS=2000  # → cada reserva tarda 2 segundos extra
# Como order-api tiene timeout de 3s → empieza a reportar timeouts
```

### ¿Cómo se comunican entre ellos?

```
1. Cliente hace POST /orders a order-api
2. order-api valida el body (product_id, quantity)
3. order-api llama a inventory-service:
   POST http://inventory-service.taller-monitoreo.svc.cluster.local:3000
        /inventory/{product_id}/reserve
        {"quantity": 2}
4. inventory-service responde:
   200 OK → stock reservado, order-api confirma la orden
   409 CONFLICT → stock insuficiente, order-api retorna error al cliente
   TIMEOUT (>3s) → order-api registra timeout y retorna 503 al cliente
```

**El DNS `inventory-service.taller-monitoreo.svc.cluster.local`** es resuelto
automáticamente por Kubernetes. No necesitas IPs ni configuración manual.

---

## PARTE 6 — Las 5 Casuísticas: Problemas Reales Simulados

Cada casuística reproduce un problema típico de producción. El flujo es:

```
ACTIVAR el problema → OBSERVAR síntomas en Grafana → DIAGNOSTICAR → RESOLVER
```

---

### 💀 Casuística 1: "El Servicio Muerto" (CrashLoopBackOff)

**Narrativa**: *"El equipo de DevOps hizo un cambio en producción el domingo a las 11pm.
Pusieron mal el nombre de la variable de entorno que apunta a inventory-service.
El lunes a las 8am, nadie puede hacer órdenes."*

**¿Qué pasa técnicamente?**
- order-api arranca, intenta conectar a una URL incorrecta
- El liveness probe falla 3 veces → K8s mata el pod → lo reinicia
- Se reinicia, falla de nuevo → `CrashLoopBackOff`

**Activar:**
```bash
kubectl set env deployment/order-api \
  INVENTORY_SERVICE_URL="http://url-incorrecta:9999" \
  -n taller-monitoreo
```

**Observar en Grafana:** Panel `💀 Pods en CrashLoopBackOff` → sube a 1

**Observar en kubectl:**
```bash
kubectl get pods -n taller-monitoreo
# NAME                    READY   STATUS             RESTARTS
# order-api-xxx           0/1     CrashLoopBackOff   5

kubectl logs -l app=order-api -n taller-monitoreo --previous
# → muestra el error del contenedor que murió
```

**Resolver:**
```bash
kubectl set env deployment/order-api \
  INVENTORY_SERVICE_URL="http://inventory-service.taller-monitoreo.svc.cluster.local:3000" \
  -n taller-monitoreo
```

**Lección:** Los probes de K8s son tu primera línea de defensa.
- **Liveness probe**: si falla → K8s reinicia el pod (detecta deadlocks, corrupciones)
- **Readiness probe**: si falla → K8s deja de enviarle tráfico (sin matar el proceso)

---

### 🧠 Casuística 2: "La Fuga de Memoria" (Memory Leak)

**Narrativa**: *"Un developer dejó accidentalmente en producción un endpoint de debugging
que acumula datos en una lista global. Cada request añade 1KB. Con el tráfico normal,
en pocas horas el pod supera su límite de memoria y el OOMKiller de Linux lo mata."*

**¿Qué pasa técnicamente?**
- Cada llamada a `/orders/stress` añade `"X" * 1024` a una lista en memoria
- La lista nunca se vacía → la memoria crece linealmente
- Cuando supera 256MB (el límite del pod) → OOMKilled → pod reinicia
- El reinicio borra la lista → empieza de cero → ciclo se repite cada pocas horas

**Activar:**
```bash
# 5000 iteraciones = ~5MB visible en Grafana
bash load-testing/stress-test.sh memory 5000

# Para disparar la alerta (85% del límite = ~218MB)
bash load-testing/stress-test.sh memory 50000
```

**Observar en Grafana:**
- Panel `🧠 Uso de Memoria` → `memory_leak_simulation_bytes` sube linealmente
- Alerta `HighMemoryUsage` → FIRING cuando supera el 85% de 256MB

**Resolver:**
```bash
# Limpiar la memoria sin reiniciar el pod
curl -X POST http://localhost:5000/orders/reset-stress

# En producción (solución de emergencia): reiniciar el pod
kubectl rollout restart deployment/order-api -n taller-monitoreo
```

**Lección:** Los `resource limits` no son restricciones arbitrarias — son protección.
Sin límites, un pod con memory leak puede consumir toda la RAM del nodo
y matar todos los otros pods del mismo nodo.

---

### 🌊 Casuística 3: "La Tormenta de Requests" (HPA Autoscaling)

**Narrativa**: *"Marketing lanzó una campaña en redes sociales un martes al mediodía
sin avisar al equipo de tech. El tráfico aumentó 10x en 5 minutos. Los usuarios
ven la app lenta y algunos requests fallan."*

**¿Qué pasa técnicamente?**
- Los requests llegan más rápido de lo que el pod puede procesarlos
- La CPU de order-api sube por encima del 70%
- El HPA detecta esto → crea pods adicionales automáticamente
- Con más pods, la carga se distribuye → la latencia baja

**Activar:**
```bash
# Terminal 1: lanzar tormenta de 500 requests en oleadas de 50
bash load-testing/stress-test.sh load 500

# Terminal 2: ver el HPA escalar en tiempo real
kubectl get hpa -n taller-monitoreo --watch
```

**Observar en Grafana:**
- Panel `⚡ Uso de CPU` → sube drásticamente
- Panel `🔢 Pods Running` → sube de 1 a 3-5 pods
- Panel `⏱️ Latencia HTTP` → sube durante la tormenta, baja cuando escala

**Cómo funciona el HPA:**
```yaml
# Si CPU promedio > 70% durante 30s → agrega hasta 2 pods/minuto (máx 5)
# Si CPU promedio < 70% durante 5min → reduce 1 pod/minuto (mín 1)
minReplicas: 1
maxReplicas: 5
averageUtilization: 70
```

**Lección:** El HPA es autoscaling **reactivo**. Para cargas predecibles
(fin de mes, black friday) existe el **Cluster Autoscaler** y el
**Vertical Pod Autoscaler (VPA)** para escalar proactivamente.

---

### 🐌 Casuística 4: "El Servicio Lento" (Latencia entre Microservicios)

**Narrativa**: *"inventory-service fue actualizado con una nueva feature que hace
una query compleja a la base de datos. La query no está optimizada y tarda 2 segundos.
order-api tiene un timeout de 3 segundos. Cuando hay carga, las órdenes empiezan a fallar."*

**¿Qué pasa técnicamente?**
- `inventory-service` tarda 2000ms en responder (simulado con `CHAOS_DELAY_MS`)
- `order-api` espera máximo 3000ms → cuando hay latencia extra → timeout
- Cada timeout se registra en `inventory_service_calls_total{status="timeout"}`

**Activar:**
```bash
# Terminal 1: inyectar delay de 2 segundos en inventory-service
bash load-testing/chaos-delay.sh enable 2000

# Terminal 2: generar tráfico para ver los timeouts
bash load-testing/stress-test.sh orders 30
```

**Observar en Grafana:**
- Panel `⏱️ Latencia de Reservas` → sube a ~2000ms
- Panel `⚠️ Timeouts Inventario` → el contador crece
- Alerta `InventoryServiceTimeouts` → FIRING

**Resolver:**
```bash
# Quitar el delay (fix del servicio lento)
bash load-testing/chaos-delay.sh disable
```

**Lección:** En microservicios, la latencia se propaga.
Si el servicio A llama al B que llama al C:
```
A ──► B (50ms) ──► C (2000ms)
   └─ A percibe 2050ms total
```
**Sin observabilidad, es imposible saber cuál de los 3 es el culpable.**
Con Grafana, en 10 segundos ves exactamente en qué servicio está la latencia.

---

### 📦 Casuística 5: "El Stock Cero" (Métricas de Negocio)

**Narrativa**: *"headset-01 es el producto estrella. Solo hay 10 unidades en stock.
Un bot de compra (o simplemente tráfico orgánico alto) lo agota en minutos.
El equipo de ventas no lo sabe hasta que los clientes se quejan en redes sociales."*

**¿Qué pasa técnicamente?**
- El stock de `headset-01` comienza en 10 unidades
- Cada venta exitosa decrementa el Gauge `inventory_stock_level`
- Cuando baja de 5 → alerta `LowInventoryStock` (warning)
- Cuando llega a 0 → alerta `ZeroInventoryStock` (critical)

**Activar:**
```bash
# El script repone stock a 15 unidades automáticamente, luego lo drena
bash load-testing/stress-test.sh drain
```

**Observar en Grafana:**
- Panel `📊 Nivel de Stock por Producto` → barra de Headset baja en tiempo real hasta 0

**Reponer stock:**
```bash
curl -X POST http://localhost:3001/inventory/headset-01/restock \
  -H "Content-Type: application/json" \
  -d '{"quantity": 50}'
```

**Lección:** La lección más importante del taller.

| Métrica | ¿Quién la entiende? | Impacto |
|---|---|---|
| CPU al 80% | Solo el equipo técnico | Ninguno para el negocio |
| Latencia 500ms | Solo el equipo técnico | Difícil de explicar al CEO |
| **Stock de headset: 0** | **Todos** — tech, ventas, CEO | **Pérdida de ingresos directa** |

Un SRE moderno no solo monitorea servidores. Monitorea el negocio.

---

## PARTE 7 — Herramientas del Taller

### Scripts disponibles

| Comando | ¿Qué hace? |
|---|---|
| `bash scripts/setup.sh` | Instala todo desde cero (Minikube, Helm, servicios) |
| `bash scripts/port-forward.sh` | Abre todos los puertos locales (Grafana, Prometheus, APIs) |
| `bash scripts/port-forward.sh stop` | Cierra los port-forwards |
| `bash scripts/teardown.sh` | Borra todos los recursos del taller |
| `bash scripts/teardown.sh full` | Borra también Minikube |
| `bash load-testing/stress-test.sh orders 20` | Crea 20 órdenes normales |
| `bash load-testing/stress-test.sh memory 5000` | Activa Casuística 2 (memory leak) |
| `bash load-testing/stress-test.sh load 500` | Activa Casuística 3 (tormenta de CPU) |
| `bash load-testing/stress-test.sh drain` | Activa Casuística 5 (agotar stock) |
| `bash load-testing/chaos-delay.sh enable 2000` | Activa Casuística 4 (servicio lento) |
| `bash load-testing/chaos-delay.sh disable` | Desactiva Casuística 4 |

### URLs del entorno (con port-forward activo)

| Servicio | URL | Credenciales |
|---|---|---|
| **Grafana** | http://localhost:3000 | admin / taller2024 |
| **Prometheus** | http://localhost:9090 | — |
| **Prometheus Targets** | http://localhost:9090/targets | debe mostrar order-api y inventory-service en UP |
| **order-api** | http://localhost:5000 | — |
| **order-api métricas** | http://localhost:5000/metrics | — |
| **inventory-service** | http://localhost:3001 | — |
| **inventory-service métricas** | http://localhost:3001/metrics | — |

### Comandos kubectl más usados en el taller

```bash
# Ver el estado de todos los pods
kubectl get pods -n taller-monitoreo

# Ver pods en tiempo real (actualiza automáticamente)
kubectl get pods -n taller-monitoreo --watch

# Ver logs del pod actual
kubectl logs -l app=order-api -n taller-monitoreo

# Ver logs del pod anterior (si crasheó)
kubectl logs -l app=order-api -n taller-monitoreo --previous

# Ver el HPA en tiempo real
kubectl get hpa -n taller-monitoreo --watch

# Ver uso de recursos de pods
kubectl top pods -n taller-monitoreo

# Ver eventos del namespace (errores, restarts, etc.)
kubectl get events -n taller-monitoreo --sort-by='.lastTimestamp'

# Descripción completa de un pod (incluye history de restarts y probes)
kubectl describe pod -l app=order-api -n taller-monitoreo
```

---

## PARTE 8 — PromQL: Las Queries Más Importantes

```promql
# ── Estado de los servicios ─────────────────────────────────────────────────
up{namespace="taller-monitoreo"}
# → 1 = UP, 0 = DOWN

# ── Órdenes y tasa ──────────────────────────────────────────────────────────
sum(orders_total)
# → Total histórico de órdenes

rate(orders_total{status="success"}[1m]) * 60
# → Órdenes exitosas por MINUTO (últimos 1m)

rate(orders_total{status="failed"}[5m]) / rate(orders_total[5m]) * 100
# → Porcentaje de error

# ── Latencia ─────────────────────────────────────────────────────────────────
histogram_quantile(0.50, rate(http_request_duration_seconds_bucket{exported_endpoint="/orders"}[5m]))
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{exported_endpoint="/orders"}[5m]))
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket{exported_endpoint="/orders"}[5m]))
# → p50 (mediana), p95 y p99 de latencia

# ── Infraestructura ──────────────────────────────────────────────────────────
rate(container_cpu_usage_seconds_total{namespace="taller-monitoreo", container!=""}[2m])
# → CPU actual de cada contenedor

container_memory_working_set_bytes{namespace="taller-monitoreo", container!=""}
# → Memoria actual (working set = memoria que realmente usa)

# ── Stock (Casuística 5) ─────────────────────────────────────────────────────
inventory_stock_level
inventory_stock_level < 5
# → Todos los productos / solo los con bajo stock

# ── Memory leak (Casuística 2) ───────────────────────────────────────────────
memory_leak_simulation_bytes
# → Bytes acumulados en la lista de stress

# ── Timeouts (Casuística 4) ──────────────────────────────────────────────────
rate(inventory_service_calls_total{status="timeout"}[5m])
# → Tasa de timeouts hacia inventory-service

# ── HPA y pods (Casuística 3) ────────────────────────────────────────────────
kube_deployment_status_replicas_available{deployment="order-api"}
# → Pods disponibles actualmente
```

> **Nota técnica**: En este taller usamos `exported_endpoint` en lugar de `endpoint`
> para filtrar la ruta `/orders`. Esto es porque el Prometheus Operator renombra
> automáticamente el label `endpoint` de la app a `exported_endpoint` cuando hay
> conflicto con el nombre del puerto del ServiceMonitor.

---

## PARTE 9 — Flujo Completo de una Orden

Para entender qué estamos monitoreando, sigue una orden de principio a fin:

```
1. Cliente:
   POST http://localhost:5000/orders
   {"product_id": "laptop-01", "quantity": 2}

2. order-api recibe el request:
   - Genera un order_id único
   - orders_pending_total.inc()     ← Gauge sube a 1
   - Inicia timer de latencia

3. order-api llama a inventory-service:
   POST http://inventory-service:3000/inventory/laptop-01/reserve
   {"quantity": 2}

4a. inventory-service (caso normal):
   - Verifica stock: 50 >= 2 → OK
   - Descuenta: stock = 48
   - inventory_stock_level.set(48)  ← Gauge actualizado
   - Retorna 200 OK

4b. inventory-service (caso Casuística 4):
   - Espera CHAOS_DELAY_MS (2000ms)
   - order-api espera... espera... 3001ms → TIMEOUT
   - inventory_service_calls_total{status="timeout"}.inc()

4c. inventory-service (caso Casuística 5):
   - Stock = 0 → retorna 409
   - low_stock_alerts_total.inc()

5. order-api procesa la respuesta:
   - orders_total{status="success"}.inc()  ← Counter sube
   - orders_pending_total.dec()             ← Gauge baja a 0
   - Registra latencia en histogram

6. Prometheus (cada 15s):
   GET http://order-api:5000/metrics
   → lee todos los contadores y gauges actualizados

7. Grafana:
   → muestra los cambios en los dashboards en el próximo refresh (10s)
```

---

## PARTE 10 — Orden Recomendado del Taller

```
Bloque 1 (30 min): Teoría
  → Partes 1-4 de esta guía
  → "¿Por qué Prometheus? ¿Qué diferencia tiene vs otros?"

Bloque 2 (20 min): Conocer los servicios
  → Parte 5 de esta guía
  → Abrir Grafana y explorar el dashboard
  → bash load-testing/stress-test.sh orders 10

Bloque 3 (60 min): Las 5 Casuísticas
  → Parte 6 de esta guía
  → Casuística 1: CrashLoopBackOff (kubectl)
  → Casuística 2: Memory Leak (Grafana lo muestra)
  → Casuística 3: HPA Autoscaling (lo más vistoso)
  → Casuística 4: Servicio Lento (ver timeouts)
  → Casuística 5: Stock Cero (métricas de negocio)

Bloque 4 (20 min): PromQL en vivo
  → Parte 8 de esta guía
  → Cada alumno escribe sus propias queries en Prometheus

Cierre (10 min):
  → bash scripts/teardown.sh
  → "¿Qué llevas a tu trabajo mañana?"
```

---

*Documentación generada para el Taller de Monitoreo Kubernetes*
*Repositorio: https://github.com/JeanSimon20/Taller_Monitoreo_Kubernetes*

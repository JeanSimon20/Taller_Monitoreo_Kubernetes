# 🎓 Guía del Profesor — Secuencia de Presentación

> Esto es tu "runbook" de clase. Léelo antes de empezar, tenlo abierto en otra pantalla mientras presentas.

---

## ⏱️ ANTES DE QUE LLEGUEN LOS ALUMNOS (15 min antes)

### Terminal 1 — Iniciar el cluster

```bash
# 1. Abrir WSL y navegar al proyecto
cd '/mnt/c/Users/jean.carlos.simon_bl/Documents/Valle Grande/Taller_Monitoreo_Kubernetes'

# 2. Verificar que Minikube está corriendo
minikube status
# Debe mostrar: host: Running, kubelet: Running, apiserver: Running

# Si NO está corriendo:
minikube start --cpus=4 --memory=6144
```

### Verificar que todo está desplegado

```bash
# Pods del taller — deben estar todos en Running
kubectl get pods -n taller-monitoreo
# NAME                                READY   STATUS    RESTARTS
# inventory-service-xxx               1/1     Running   0
# order-api-xxx                       1/1     Running   0

# Pods de monitoreo — todos Running
kubectl get pods -n monitoring
# monitoring-grafana-xxx              3/3     Running   0   ← importante 3/3
# prometheus-xxx                      2/2     Running   0
# alertmanager-xxx                    2/2     Running   0
```

### Terminal 2 — Iniciar port-forwards (déjala abierta toda la clase)

```bash
cd '/mnt/c/Users/jean.carlos.simon_bl/Documents/Valle Grande/Taller_Monitoreo_Kubernetes'
bash scripts/port-forward.sh
```

✅ Cuando veas `OK` en todos los servicios, abre el navegador.

### Abrir en el navegador (Windows)

| Servicio | URL | Credenciales |
|---|---|---|
| 📊 **Grafana** | http://localhost:3000 | admin / taller2024 |
| 🔥 **Prometheus** | http://localhost:9090 | — |
| 📦 **order-api** | http://localhost:5000/health | — |
| 🏭 **inventory** | http://localhost:3001/health | — |

### En Grafana, ir al dashboard del taller

```
Menú izquierdo → Dashboards → Taller Kubernetes → "🎓 Taller K8s — Monitoreo Microservicios"
```

---

## 🚀 SECUENCIA DE LA CLASE

### MÓDULO 1 — Introducción (5 min)

**Mostrar en pantalla**: El dashboard de Grafana vacío (sin datos aún)

**Lo que dices**:
> "Esto es lo que vamos a construir hoy. Ahora mismo ven un dashboard vacío porque
> nadie está usando el sistema. En 2 horas, van a entender cada panel que ven aquí."

---

### MÓDULO 2 — Los Microservicios (10 min)

**Mostrar en Terminal**:
```bash
# Ver los pods corriendo
kubectl get pods -n taller-monitoreo

# Ver las métricas RAW de order-api (esto es lo que ve Prometheus)
curl http://localhost:5000/metrics
# Salida: cientos de líneas de métricas en formato texto

# Ver el health check
curl http://localhost:5000/health
# {"status": "healthy", "service": "order-api", ...}

# Ver el inventario
curl http://localhost:3001/inventory
# {"products": [...], "total_products": 5}
```

**Punto clave para explicar**:
> "Fíjense: con `curl /metrics` ven texto plano. Eso es todo lo que Prometheus hace —
> viene cada 15 segundos y pide esa URL. Nada de agentes, nada de magic."

---

### MÓDULO 3 — Prometheus (10 min)

**Abrir**: http://localhost:9090/targets

**Mostrar**: Los dos targets `order-api` e `inventory-service` en estado **UP** (verde)

```
State: UP ✅    order-api          http://10.x.x.x:5000/metrics
State: UP ✅    inventory-service  http://10.x.x.x:3000/metrics
```

**Ir a**: http://localhost:9090 → pestaña Graph

**Escribir estas queries en vivo**:
```promql
# Query 1: ¿Los servicios están vivos?
up{namespace="taller-monitoreo"}
# Resultado: 1 = UP, 0 = DOWN

# Query 2: Stock actual de inventario
inventory_stock_level
# Resultado: una serie por cada producto con su cantidad

# Query 3: Crear tráfico primero y luego mostrar
rate(orders_total[5m])
```

---

### MÓDULO 4 — Grafana (5 min)

**Abrir el dashboard**: `🎓 Taller K8s — Monitoreo Microservicios`

**Crear tráfico normal para que aparezcan datos**:

```bash
# En una terminal nueva (Terminal 3):
cd '/mnt/c/Users/jean.carlos.simon_bl/Documents/Valle Grande/Taller_Monitoreo_Kubernetes'
bash load-testing/stress-test.sh orders 20
```

**Mostrar en Grafana** (esperar 15-30 segundos para que aparezcan datos):
- Panel `📈 Tasa de Órdenes por Minuto` → línea verde subiendo
- Panel `⏱️ Latencia HTTP — p50, p95, p99` → latencias muy bajas (~10-50ms)
- Panel `📊 Nivel de Stock` → barras con colores según cantidad

---

## 💥 CASUÍSTICAS EN VIVO

> Cada casuística: **anunciar** → **ejecutar** → **observar en Grafana** → **explicar** → **arreglar**

---

### 💀 CASUÍSTICA 1: El Servicio Muerto (5 min)

**Narración**: *"Son las 8am del lunes. Alguien actualizó una variable de entorno mal."*

**Terminal 3** — Romper el servicio:
```bash
kubectl set env deployment/order-api \
  INVENTORY_SERVICE_URL="http://wrong-url:9999" \
  -n taller-monitoreo
```

**Observar en Grafana** (en ~30 segundos):
- Panel `🟢 Estado order-api` → se pone **ROJO** con ❌

**Observar en Prometheus** → http://localhost:9090/alerts:
- Alerta `OrderApiDown` en estado **FIRING** 🔴

**Mostrar el síntoma**:
```bash
kubectl get pods -n taller-monitoreo
# order-api-xxx   0/1   CrashLoopBackOff   3   2m
kubectl logs -l app=order-api -n taller-monitoreo --previous
```

**Arreglar**:
```bash
kubectl set env deployment/order-api \
  INVENTORY_SERVICE_URL="http://inventory-service.taller-monitoreo.svc.cluster.local:3000" \
  -n taller-monitoreo
kubectl rollout status deployment/order-api -n taller-monitoreo
```

**Lección**: Liveness Probe vs Readiness Probe

---

### 🧠 CASUÍSTICA 2: La Fuga de Memoria (5 min)

**Narración**: *"Un developer dejó un bug en producción. Cada request acumula 1KB en memoria."*

**Terminal 3** — Activar el leak:
```bash
bash load-testing/stress-test.sh memory 80
```

**Observar en Grafana**:
- Panel `🧠 Uso de Memoria — Casuística 2` → línea sube en diagonal
- Panel `🧠 Memory Leak (Casuística 2)` (stat card) → número aumentando

**Pregunta al grupo**: *"¿Cuándo actuaría Kubernetes aquí? ¿Cuál es el límite?"*
> Respuesta: cuando supere 256Mi → OOMKill → pod se reinicia

**Arreglar**:
```bash
curl -s -X POST http://localhost:5000/orders/reset-stress
# {"message": "Memoria liberada correctamente"}
```

---

### 🌊 CASUÍSTICA 3: La Tormenta de Requests (8 min)

**Narración**: *"Marketing lanzó una campaña sin avisar. El tráfico subió 10x en 5 minutos."*

**Abrir Terminal adicional** para monitorear el HPA:
```bash
kubectl get hpa -n taller-monitoreo --watch
```

**Terminal 3** — Lanzar la tormenta:
```bash
bash load-testing/stress-test.sh load 300
```

**Observar en Grafana**:
- Panel `⚡ Uso de CPU` → sube rápido al 80-90%
- Panel `⏱️ Latencia HTTP — p50, p95, p99` → p99 sube a 1-3 segundos

**Observar el HPA**:
```
NAME            TARGETS      REPLICAS
order-api-hpa   85%/70%      1 → 3  ← K8s escala automáticamente!
```

- Panel `🔢 Pods Running — order-api` → cambia de 1 a 3

**Pregunta al grupo**: *"¿Por qué la latencia BAJA cuando llegan los pods nuevos?"*

---

### 🐌 CASUÍSTICA 4: El Servicio Lento (5 min)

**Narración**: *"inventory-service tiene una query lenta. order-api tiene timeout de 3s."*

**Terminal 3** — Inyectar delay de 2 segundos:
```bash
bash load-testing/chaos-delay.sh enable 2000
```

**Generar tráfico**:
```bash
for i in {1..10}; do
  curl -s -X POST http://localhost:5000/orders \
    -H "Content-Type: application/json" \
    -d '{"product_id": "laptop-01", "quantity": 1}'
  echo ""
  sleep 1
done
```

**Observar en Grafana**:
- Panel `⏱️ Latencia de Reservas — inventory-service` → sube a 2+ segundos
- Panel `⚠️ Timeouts Inventario` → contador crece
- Alerta `InventoryServiceTimeouts` → FIRING

**Arreglar**:
```bash
bash load-testing/chaos-delay.sh disable
```

---

### 📦 CASUÍSTICA 5: El Stock Cero (5 min)

**Narración**: *"El headset gaming es el más popular. Solo quedan 10 unidades."*

**Terminal 3** — Agotar el stock:
```bash
bash load-testing/stress-test.sh drain
```

**Observar en Grafana**:
- Panel `📊 Nivel de Stock por Producto` → barra de **Headset Gaming** baja a 0
- Alerta `LowInventoryStock` → FIRING (< 5 unidades)
- Alerta `ZeroInventoryStock` → FIRING (stock = 0)

**Pregunta al grupo**: *"¿Qué diferencia esta alerta de las anteriores?"*
> Esta es una **métrica de negocio**, no de infraestructura.

**Reponer stock**:
```bash
curl -s -X POST http://localhost:3001/inventory/headset-01/restock \
  -H "Content-Type: application/json" \
  -d '{"quantity": 50}'
```

---

## 🏁 CIERRE DE LA CLASE (5 min)

### Mostrar el dashboard completo con todas las métricas

Cambiar el rango de tiempo en Grafana a **"Last 1 hour"** para mostrar la historia de todo lo que pasaron.

### Mensaje final para el grupo

> "En las últimas 2 horas rompimos 5 servicios y los diagnosticamos todos con Prometheus
> y Grafana. Esto es lo que hace un SRE todos los días.
>
> La diferencia entre un sistema observable y uno que no lo es: en el primero,
> cuando algo falla a las 3am, sabes exactamente qué pasó y dónde. En el otro,
> rezas."

### Comandos de limpieza (al final)

```bash
# Detener port-forwards (Ctrl+C en Terminal 2)

# Limpiar todo el entorno
bash scripts/teardown.sh

# O solo pausar Minikube (más rápido que reiniciar)
minikube stop
```

---

## 🆘 TROUBLESHOOTING RÁPIDO

| Síntoma | Causa | Fix rápido |
|---|---|---|
| Grafana no abre en localhost:3000 | port-forward no está corriendo | `bash scripts/port-forward.sh` |
| Panel Grafana sin datos | Prometheus aún no hizo scrape | Esperar 15-30 seg, refrescar |
| Pod en CrashLoopBackOff | Variable de entorno mal (Casuística 1) | Ver comando arreglar arriba |
| HPA no escala | metrics-server no activo | `minikube addons enable metrics-server` |
| `minikube ip` no accesible desde Windows | Es IP interna de WSL | Usar `localhost` con port-forward |
| Targets DOWN en Prometheus | ServiceMonitor no detectado | `kubectl get servicemonitors -n taller-monitoreo` |

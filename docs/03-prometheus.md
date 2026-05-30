# 📖 Módulo 3 — Prometheus en Kubernetes

## ¿Cómo funciona Prometheus?

```
Prometheus ──► GET /metrics ──► Tu servicio
    │
    ▼
TSDB (Time Series Database)
    │
    ▼
PromQL Queries
    │
    ▼
Grafana / AlertManager
```

Prometheus es un sistema de **pull** — él va a buscar las métricas, no las métricas vienen a él.
Esto lo diferencia de sistemas como StatsD o CloudWatch que usan **push**.

**Ventaja del pull**: Si el servicio muere, Prometheus lo detecta inmediatamente
porque deja de recibir respuesta en el scrape.

---

## El Prometheus Operator y sus CRDs

En Kubernetes, instalamos el **Prometheus Operator** que añade objetos nuevos a K8s:

| CRD | Función |
|---|---|
| `Prometheus` | Define una instancia de Prometheus |
| `ServiceMonitor` | Le dice a Prometheus qué Services monitorear |
| `PodMonitor` | Le dice a Prometheus qué Pods monitorear directamente |
| `PrometheusRule` | Define reglas de alerta en PromQL |
| `AlertManager` | Define cómo enviar las alertas |

```bash
# Ver todos los CRDs instalados por el Prometheus Operator
kubectl get crds | grep monitoring.coreos.com
```

---

## El ServiceMonitor explicado

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: order-api-monitor
spec:
  selector:
    matchLabels:
      app: order-api          # ← Busca Services con este label
  endpoints:
    - port: http              # ← Nombre del puerto en el Service
      path: /metrics          # ← Ruta de las métricas
      interval: 15s           # ← Frecuencia de scrape
```

**Flujo completo**:
1. El `ServiceMonitor` selecciona el Service `order-api`
2. El Prometheus Operator le dice a Prometheus: "raspa ese Service"
3. Prometheus hace `GET http://order-api:5000/metrics` cada 15s
4. Los datos se guardan en la TSDB de Prometheus
5. Grafana consulta Prometheus con PromQL

---

## PromQL — El Lenguaje de Consultas

### Sintaxis básica

```promql
# Métrica simple — devuelve el valor actual
orders_total

# Con filtros de label
orders_total{status="success"}
orders_total{status=~"success|failed"}  # regex: success O failed
orders_total{status!="failed"}          # negación

# Con función de rate (tasa de cambio)
rate(orders_total[5m])                  # tasa por segundo en los últimos 5m
rate(orders_total[5m]) * 60            # tasa por minuto

# Operaciones matemáticas
rate(orders_total{status="failed"}[5m])
/
rate(orders_total[5m])
# → Porcentaje de órdenes fallidas
```

### Funciones importantes

```promql
# histogram_quantile — Calcular percentiles
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
#                  ^^^^  ← 0.50=p50, 0.95=p95, 0.99=p99

# sum — Sumar series
sum(orders_total) by (status)

# avg_over_time — Promedio histórico
avg_over_time(inventory_stock_level[1h])

# increase — Incremento en un período
increase(orders_total[1h])  # órdenes en la última hora

# absent — ¿Existe la métrica? (útil para alertas de "servicio caído")
absent(up{job="order-api"})  # true si order-api está DOWN
```

---

## Verificar que Prometheus ve tus servicios

```bash
# Port-forward a Prometheus
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090 -n monitoring

# Abrir: http://localhost:9090/targets
# Buscar "taller-monitoreo" — deben estar en estado UP
```

**Troubleshooting si aparecen como DOWN**:
```bash
# 1. Verificar que el Service tiene el label correcto
kubectl get svc -n taller-monitoreo --show-labels

# 2. Verificar que el ServiceMonitor existe
kubectl get servicemonitors -n taller-monitoreo

# 3. Ver logs del Prometheus Operator
kubectl logs -l app.kubernetes.io/name=prometheus-operator -n monitoring
```

---

## AlertManager

AlertManager recibe las alertas de Prometheus y decide qué hacer con ellas:

```
Prometheus ──► ALERTA ──► AlertManager ──► Slack/Email/PagerDuty
                              │
                    (agrupa, silencia, enruta)
```

### Ver alertas activas

```bash
# En Prometheus UI: http://localhost:9090/alerts
# En AlertManager: 
kubectl port-forward svc/monitoring-kube-prometheus-alertmanager 9093 -n monitoring
# Abrir: http://localhost:9093
```

---

## Checkpoint del Módulo 3 ✅

```bash
# 1. Verificar targets en Prometheus (ambos deben estar UP)
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090 -n monitoring &
sleep 3
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep '"health"'

# 2. Verificar que las métricas de los servicios llegan a Prometheus
curl -s "http://localhost:9090/api/v1/query?query=up{namespace='taller-monitoreo'}"
```

Deberías ver `"result":[{"metric":{"job":"order-api"},"value":[...,"1"]}]`
El valor `"1"` significa UP. `"0"` significa DOWN.

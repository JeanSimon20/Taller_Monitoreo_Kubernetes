# 🎓 Taller: Monitoreo en Kubernetes con Prometheus & Grafana

> **Bienvenido al taller más práctico de Kubernetes que vas a tomar.**
> No enseñamos teoría en el aire — desplegamos, rompemos y monitoreamos.

---

## 🏗️ Arquitectura del Taller

```
┌─────────────────────────────────────────────────────────────────┐
│                    MINIKUBE CLUSTER LOCAL                       │
│                   namespace: taller-monitoreo                   │
│                                                                 │
│  ┌─────────────────┐   HTTP    ┌──────────────────────────┐    │
│  │   order-api     │ ────────► │   inventory-service      │    │
│  │  Python/Flask   │           │    Node.js/Express        │    │
│  │  Puerto: 5000   │           │    Puerto: 3000           │    │
│  └────────┬────────┘           └─────────────┬────────────┘    │
│           │ /metrics                         │ /metrics        │
│           └──────────────┬───────────────────┘                 │
│                          ▼                                      │
│              ┌───────────────────────┐                         │
│              │      PROMETHEUS       │                         │
│              │  (scrape cada 15s)    │                         │
│              └───────────┬───────────┘                         │
│                          │                                      │
│              ┌───────────▼───────────┐                         │
│              │       GRAFANA         │                         │
│              │  Dashboards + Alertas │                         │
│              └───────────────────────┘                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📋 Módulos del Taller

| # | Módulo | Tiempo | Archivo |
|---|---|---|---|
| 1 | Fundamentos de Observabilidad | 30 min | [01-fundamentos.md](docs/01-fundamentos.md) |
| 2 | Los Microservicios | 45 min | [02-microservicios.md](docs/02-microservicios.md) |
| 3 | Prometheus en Kubernetes | 45 min | [03-prometheus.md](docs/03-prometheus.md) |
| 4 | Grafana — Dashboards y Alertas | 30 min | [04-grafana.md](docs/04-grafana.md) |
| 5 | **Casuísticas en Vivo** ⭐ | 60 min | [05-casuisticas.md](docs/05-casuisticas.md) |

---

## 🚀 Inicio Rápido

### Prerequisitos
- Docker Desktop instalado y corriendo
- [Minikube](https://minikube.sigs.k8s.io/docs/start/) instalado
- [kubectl](https://kubernetes.io/docs/tasks/tools/) instalado
- [Helm](https://helm.sh/docs/intro/install/) instalado

### Setup en un comando

```bash
bash scripts/setup.sh
```

> ⏱️ **Tiempo estimado**: 5-8 minutos (incluye descarga de imágenes de Helm)

### Acceder a los servicios

```bash
# Grafana (usuario: admin, contraseña: taller2024)
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
# Abrir: http://localhost:3000

# Prometheus
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090 -n monitoring
# Abrir: http://localhost:9090

# APIs directamente (sin port-forward)
MINIKUBE_IP=$(minikube ip)
curl http://$MINIKUBE_IP:30500/health    # order-api
curl http://$MINIKUBE_IP:30300/health   # inventory-service
```

---

## 💥 Las 5 Casuísticas

| # | Nombre | Comando | Lo que ves en Grafana |
|---|---|---|---|
| 1 | 💀 El Servicio Muerto | `kubectl set env deployment/order-api BAD_VAR=true -n taller-monitoreo` | Target DOWN en Prometheus, alerta CrashLoopBackOff |
| 2 | 🧠 La Fuga de Memoria | `bash load-testing/stress-test.sh memory 100` | `memory_leak_simulation_bytes` sube linealmente |
| 3 | 🌊 La Tormenta de Requests | `bash load-testing/stress-test.sh load 500` | CPU sube, HPA escala pods, latencia se normaliza |
| 4 | 🐌 El Servicio Lento | `bash load-testing/chaos-delay.sh enable 2000` | Latencia p95 > 2s, timeouts crecen |
| 5 | 📦 El Stock Cero | `bash load-testing/stress-test.sh drain` | Gauge de stock baja a 0, alerta de negocio |

---

## 📁 Estructura del Proyecto

```
Taller_Monitoreo_Kubernetes/
├── README.md                    ← Estás aquí
├── docs/                        ← Documentación del taller
├── microservices/
│   ├── order-api/               ← Microservicio Python/Flask
│   └── inventory-service/       ← Microservicio Node.js
├── k8s/
│   ├── namespace.yaml
│   ├── order-api/               ← Deployment, Service, HPA
│   ├── inventory-service/       ← Deployment, Service
│   └── monitoring/              ← Prometheus, Grafana, Alertas
├── load-testing/
│   ├── stress-test.sh           ← Casuísticas 2, 3, 5
│   └── chaos-delay.sh           ← Casuística 4
└── scripts/
    ├── setup.sh                 ← Setup completo
    └── teardown.sh              ← Limpieza
```

---

## 🆘 Troubleshooting

### Los pods no arrancan (ImagePullBackOff)
```bash
# Asegúrate de que las imágenes están en el daemon de Minikube
eval $(minikube docker-env)
docker images | grep -E "order-api|inventory-service"

# Si no aparecen, recontruirlas:
bash scripts/build-images.sh
```

### Prometheus no ve los servicios (targets DOWN)
```bash
# Verificar que los ServiceMonitors existen
kubectl get servicemonitors -n taller-monitoreo

# Verificar que los pods tienen el label correcto
kubectl get pods -n taller-monitoreo --show-labels
```

### Grafana no muestra datos
```bash
# Esperar 2-3 minutos para que Prometheus haga el primer scrape
# Luego verificar en Prometheus: http://localhost:9090/targets
# Si el target está UP, los datos llegarán a Grafana en segundos
```

---

*Taller creado para el curso de Kubernetes — Valle Grande*
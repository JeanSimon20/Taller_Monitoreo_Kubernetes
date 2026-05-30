/**
 * =============================================================================
 * INVENTORY-SERVICE — Microservicio de Gestión de Inventario
 * =============================================================================
 * PROFESOR DICE:
 *   Este servicio en Node.js muestra que Prometheus es agnóstico al lenguaje.
 *   La librería 'prom-client' en Node funciona exactamente igual que
 *   'prometheus_client' en Python — los mismos 4 tipos de métricas.
 *
 *   MÉTRICAS CLAVE DE ESTE SERVICIO:
 *   - stock_level (Gauge)         → nivel actual de inventario por producto
 *   - inventory_requests_total    → total de requests al servicio
 *   - reservation_duration_sec    → tiempo que tarda en procesar una reserva
 *   - low_stock_alerts_total      → contador de alertas de bajo stock
 *
 *   LA PREGUNTA PEDAGÓGICA CLAVE:
 *   ¿Por qué un Gauge y no un Counter para el stock?
 *   → Porque el stock SUBE (reposición) y BAJA (ventas). Un Counter solo sube.
 * =============================================================================
 */

const express = require("express");
const client = require("prom-client");

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3000;
// Variable de entorno para habilitar el delay artificial (Casuística 4)
const CHAOS_DELAY_MS = parseInt(process.env.CHAOS_DELAY_MS || "0");

// ─── Inventario en Memoria ─────────────────────────────────────────────────
// PROFESOR DICE: En producción esto sería una base de datos.
// Para el taller usamos memoria para mantener el setup simple.
const inventory = {
  "laptop-01": { name: "Laptop Pro 15\"", stock: 50, price: 1200.00 },
  "mouse-01":  { name: "Mouse Inalámbrico", stock: 200, price: 25.00 },
  "kb-01":     { name: "Teclado Mecánico", stock: 75, price: 89.00 },
  "monitor-01":{ name: "Monitor 4K 27\"", stock: 30, price: 450.00 },
  "headset-01":{ name: "Headset Gaming", stock: 10, price: 150.00 }, // Stock bajo para demo
};

// ─── Registro de Métricas ──────────────────────────────────────────────────
// Creamos un registro personalizado (no el registro global)
// PROFESOR DICE: Esto es una buena práctica — evita conflictos si
// tienes múltiples instancias o tests en el mismo proceso.
const register = new client.Registry();

// Métricas por defecto de Node.js (CPU, memoria, event loop, etc.)
// PROFESOR DICE: Con una sola línea obtienes +30 métricas del runtime de Node.
client.collectDefaultMetrics({ register });

// ── Métrica 1: Counter — Total de requests por endpoint y método ──
const requestsTotal = new client.Counter({
  name: "inventory_requests_total",
  help: "Total de requests HTTP recibidos por el inventory-service",
  labelNames: ["method", "endpoint", "status_code"],
  registers: [register],
});

// ── Métrica 2: Gauge — Nivel de stock por producto ────────────────
// PROFESOR DICE: Esta métrica es la más importante de negocio.
// Una alerta "stock < 5" en Grafana puede evitar quedarse sin producto.
const stockLevel = new client.Gauge({
  name: "inventory_stock_level",
  help: "Nivel actual de stock por producto",
  labelNames: ["product_id", "product_name"],
  registers: [register],
});

// ── Métrica 3: Histogram — Duración de operaciones de reserva ─────
const reservationDuration = new client.Histogram({
  name: "inventory_reservation_duration_seconds",
  help: "Duración de las operaciones de reserva de stock en segundos",
  labelNames: ["product_id", "result"],
  // PROFESOR DICE: Estos buckets miden desde 1ms hasta 10 segundos
  // Si el p95 supera 1 segundo, hay un problema de rendimiento.
  buckets: [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.5, 1.0, 5.0, 10.0],
  registers: [register],
});

// ── Métrica 4: Counter — Alertas de bajo stock ────────────────────
// PROFESOR DICE: Esta es una métrica de NEGOCIO, no de infraestructura.
// Los SREs modernos monitorean el negocio, no solo los servidores.
const lowStockAlerts = new client.Counter({
  name: "inventory_low_stock_alerts_total",
  help: "Número de veces que un producto llegó a nivel de stock bajo (< 5 unidades)",
  labelNames: ["product_id"],
  registers: [register],
});

// ── Métrica 5: Gauge — Delay de chaos (para Casuística 4) ─────────
const chaosDelayGauge = new client.Gauge({
  name: "inventory_chaos_delay_ms",
  help: "Delay artificial configurado (ms) — solo para demos de casuísticas",
  registers: [register],
});

// Inicializar los gauges de stock con los valores actuales
function initializeStockMetrics() {
  for (const [id, product] of Object.entries(inventory)) {
    stockLevel.labels(id, product.name).set(product.stock);
  }
  chaosDelayGauge.set(CHAOS_DELAY_MS);
  console.log(`[INFO] Métricas de stock inicializadas para ${Object.keys(inventory).length} productos`);
  console.log(`[INFO] Chaos delay configurado: ${CHAOS_DELAY_MS}ms`);
}

// ─── Middleware de Métricas ────────────────────────────────────────────────
// PROFESOR DICE: Este middleware registra automáticamente TODAS las requests.
// Es el equivalente del decorador @track_request_metrics en Python.
app.use((req, res, next) => {
  const start = Date.now();
  res.on("finish", () => {
    const duration = (Date.now() - start) / 1000;
    requestsTotal.labels(req.method, req.path, res.statusCode.toString()).inc();
    console.log(`[${req.method}] ${req.path} → ${res.statusCode} (${(duration * 1000).toFixed(1)}ms)`);
  });
  next();
});

// ─── Función de Delay Artificial ──────────────────────────────────────────
/**
 * CASUÍSTICA 4 — EL SERVICIO LENTO
 * Esta función introduce un delay configurable via variable de entorno.
 * En la demo, hacemos: kubectl set env deployment/inventory-service CHAOS_DELAY_MS=2000
 * Y vemos en Grafana cómo la latencia de order-api aumenta inmediatamente.
 */
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// ─── Endpoints ────────────────────────────────────────────────────────────

/**
 * GET /health — Health Check
 * PROFESOR DICE: En Kubernetes, configuramos este endpoint como:
 *   livenessProbe: /health  → ¿Está vivo el proceso?
 *   readinessProbe: /health → ¿Está listo para recibir tráfico?
 */
app.get("/health", (req, res) => {
  res.status(200).json({
    status: "healthy",
    service: "inventory-service",
    version: "1.0.0",
    chaos_delay_ms: CHAOS_DELAY_MS,
    timestamp: Date.now(),
  });
});

/**
 * GET /metrics — Endpoint de Prometheus
 * PROFESOR DICE: Este es el endpoint que Prometheus "raspa" cada 15 segundos.
 * El formato que genera prom-client es el estándar OpenMetrics.
 */
app.get("/metrics", async (req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});

/**
 * GET /inventory — Lista todo el inventario disponible
 */
app.get("/inventory", (req, res) => {
  const products = Object.entries(inventory).map(([id, product]) => ({
    id,
    ...product,
    low_stock: product.stock < 5,
  }));

  res.status(200).json({
    products,
    total_products: products.length,
    low_stock_products: products.filter((p) => p.low_stock).length,
  });
});

/**
 * GET /inventory/:id — Consulta stock de un producto específico
 */
app.get("/inventory/:id", (req, res) => {
  const product = inventory[req.params.id];

  if (!product) {
    return res.status(404).json({ error: `Producto '${req.params.id}' no encontrado` });
  }

  res.status(200).json({
    id: req.params.id,
    ...product,
    low_stock: product.stock < 5,
  });
});

/**
 * POST /inventory/:id/reserve — Reserva stock de un producto
 *
 * PROFESOR DICE: Este es el endpoint más interesante porque:
 * 1. Tiene delay artificial configurable (Casuística 4)
 * 2. Puede retornar 409 cuando hay stock insuficiente (Casuística 5)
 * 3. Actualiza el Gauge de stock en tiempo real (visible en Grafana)
 */
app.post("/inventory/:id/reserve", async (req, res) => {
  const startTime = Date.now();
  const productId = req.params.id;
  const { quantity } = req.body;

  if (!quantity || quantity <= 0) {
    return res.status(400).json({ error: "Se requiere 'quantity' mayor a 0" });
  }

  const product = inventory[productId];
  if (!product) {
    return res.status(404).json({ error: `Producto '${productId}' no encontrado` });
  }

  // ── CASUÍSTICA 4: Delay Artificial ──────────────────────────────
  // Si CHAOS_DELAY_MS > 0, simulamos un servicio lento.
  // Esto hace que order-api empiece a reportar timeouts.
  if (CHAOS_DELAY_MS > 0) {
    console.warn(`[⚠️  CHAOS] Aplicando delay de ${CHAOS_DELAY_MS}ms para producto ${productId}`);
    await sleep(CHAOS_DELAY_MS);
  }

  // ── CASUÍSTICA 5: Stock Insuficiente ────────────────────────────
  if (product.stock < quantity) {
    const duration = (Date.now() - startTime) / 1000;
    reservationDuration.labels(productId, "insufficient_stock").observe(duration);

    console.warn(`[⚠️  STOCK] Stock insuficiente para ${productId}: tiene ${product.stock}, pide ${quantity}`);

    // Si el stock es 0, disparamos la alerta de negocio
    if (product.stock === 0) {
      lowStockAlerts.labels(productId).inc();
      console.error(`[🚨 ALERTA] Producto ${productId} SIN STOCK — ${product.name}`);
    }

    return res.status(409).json({
      error: "Stock insuficiente",
      product_id: productId,
      available: product.stock,
      requested: quantity,
    });
  }

  // ── Reserva Exitosa ─────────────────────────────────────────────
  product.stock -= quantity;

  // Actualizamos el Gauge de stock — Grafana lo reflejará en segundos
  stockLevel.labels(productId, product.name).set(product.stock);

  // ── Verificamos si quedamos en stock bajo ─────────────────────
  if (product.stock < 5) {
    lowStockAlerts.labels(productId).inc();
    console.warn(`[⚠️  LOW_STOCK] ${product.name} (${productId}) stock crítico: ${product.stock} unidades`);
  }

  const duration = (Date.now() - startTime) / 1000;
  reservationDuration.labels(productId, "success").observe(duration);

  console.log(`[✅ RESERVA] ${quantity}x ${product.name} — stock restante: ${product.stock}`);

  return res.status(200).json({
    message: "Stock reservado exitosamente",
    product_id: productId,
    product_name: product.name,
    reserved: quantity,
    remaining_stock: product.stock,
    low_stock_warning: product.stock < 5,
  });
});

/**
 * POST /inventory/:id/restock — Repone stock (para resetear demos)
 */
app.post("/inventory/:id/restock", (req, res) => {
  const { quantity } = req.body;
  const product = inventory[req.params.id];

  if (!product) {
    return res.status(404).json({ error: "Producto no encontrado" });
  }

  product.stock += parseInt(quantity || 50);
  stockLevel.labels(req.params.id, product.name).set(product.stock);

  console.log(`[🔄 RESTOCK] ${product.name}: stock repuesto a ${product.stock}`);
  res.status(200).json({ message: "Stock repuesto", new_stock: product.stock });
});

// ─── Start Server ──────────────────────────────────────────────────────────
initializeStockMetrics();

app.listen(PORT, "0.0.0.0", () => {
  console.log(`\n🚀 inventory-service corriendo en puerto ${PORT}`);
  console.log(`📊 Métricas disponibles en: http://localhost:${PORT}/metrics`);
  console.log(`🏥 Health check en:         http://localhost:${PORT}/health`);
  console.log(`📦 Productos en inventario: ${Object.keys(inventory).length}`);
  if (CHAOS_DELAY_MS > 0) {
    console.warn(`\n⚠️  MODO CHAOS ACTIVO — delay de ${CHAOS_DELAY_MS}ms en reservas`);
  }
  console.log("\n");
});

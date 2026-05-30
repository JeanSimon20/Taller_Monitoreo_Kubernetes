# =============================================================================
# Dockerfile — inventory-service (Node.js/Express)
# =============================================================================
# PROFESOR DICE: Mismo patrón multi-stage que order-api.
# Consistencia entre servicios facilita el mantenimiento del equipo.
# =============================================================================

# ── Stage 1: Instalación de dependencias ─────────────────────────────────────
FROM node:20-slim AS builder

WORKDIR /app

# Copiamos solo package.json primero para aprovechar el cache de Docker
COPY package*.json ./
RUN npm ci --only=production


# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM node:20-slim AS runtime

# PROFESOR DICE: El usuario 'node' ya existe en la imagen oficial de Node.
# No necesitamos crearlo — buena práctica usar los usuarios del runtime oficial.
WORKDIR /app

# Copiamos dependencias del stage anterior
COPY --from=builder /app/node_modules ./node_modules

# Copiamos el código
COPY server.js .
COPY package.json .

# Cambiamos al usuario sin privilegios
USER node

# Variables de entorno por defecto
ENV PORT=3000
ENV NODE_ENV=production
ENV CHAOS_DELAY_MS=0

EXPOSE 3000

# Health check interno
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', (r) => process.exit(r.statusCode === 200 ? 0 : 1))"

CMD ["node", "server.js"]

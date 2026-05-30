# =============================================================================
# Dockerfile — order-api (Python/Flask)
# =============================================================================
# PROFESOR DICE: Usamos multi-stage build para:
#   1. Separar el entorno de BUILD del de RUNTIME
#   2. La imagen final es más pequeña y segura (no incluye compiladores)
#   3. En producción, las imágenes pequeñas = arranque más rápido en K8s
# =============================================================================

# ── Stage 1: Builder ──────────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /app

# Copiamos solo requirements primero — Docker cachea esta capa
# si el código cambia pero no las dependencias, el build es más rápido
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt


# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

# PROFESOR DICE: Nunca corras contenedores como root en producción.
# Creamos un usuario sin privilegios para ejecutar la app.
RUN useradd --create-home --shell /bin/bash appuser
WORKDIR /app

# Copiamos las dependencias del stage anterior
COPY --from=builder /root/.local /home/appuser/.local

# Copiamos el código de la aplicación
COPY app.py .

# Cambiamos al usuario sin privilegios
USER appuser

# Variables de entorno por defecto
ENV PORT=5000
ENV PYTHONUNBUFFERED=1
ENV PATH=/home/appuser/.local/bin:$PATH

# Puerto que expone el contenedor
EXPOSE 5000

# Health check interno del contenedor
# PROFESOR DICE: Esto es diferente al Kubernetes readiness probe.
# Docker también puede saber si el contenedor está sano.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

# Usamos gunicorn en producción (no el servidor de desarrollo de Flask)
# PROFESOR DICE: gunicorn maneja múltiples workers y es mucho más eficiente
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--threads", "4", "--timeout", "60", "app:app"]

FROM node:16 AS frontend-builder

WORKDIR /app/frontend
COPY src/frontend/ .
RUN npm ci && npm run build

FROM python:3.9-slim

WORKDIR /app

# Copy frontend build
COPY --from=frontend-builder /app/frontend/build /app/static

# Install backend dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy backend code
COPY src/backend/ .

# Default values for customizable settings
ENV PORT=8000
ENV HEALTH_CHECK_PATH=/health
ENV METRICS_PATH=/metrics

# Expose the container port (can be overridden)
EXPOSE ${PORT}

# Add health check
HEALTHCHECK --interval=5s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:${PORT}${HEALTH_CHECK_PATH} || exit 1

# Run the application
CMD ["sh", "-c", "python app.py --port=${PORT} --health-path=${HEALTH_CHECK_PATH} --metrics-path=${METRICS_PATH}"]
# Build stage
FROM node:18-alpine as build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Production stage
FROM nginx:alpine
COPY --from=build /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Add Prometheus monitoring
RUN apk add --no-cache curl
COPY metrics-exporter.js /usr/share/nginx/html/metrics-exporter.js

# Add version info for canary tracking
ARG BUILD_DATE
ARG VCS_REF
LABEL org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.title="SMU Frontend" \
    org.opencontainers.image.revision="${VCS_REF}" \
    org.opencontainers.image.version="${VCS_REF}"

# Expose port
EXPOSE 80

# Health check for Kubernetes
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
FROM node:18-alpine

# Create app directory
WORKDIR /usr/src/app

# Install app dependencies
COPY package*.json ./
RUN npm ci --only=production

# Bundle app source
COPY . .

# Set environment variables
ENV NODE_ENV production
ENV PORT 3000

# Add Prometheus client
RUN npm install prom-client

# Add version info for canary tracking
ARG BUILD_DATE
ARG VCS_REF
LABEL org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.title="SMU Backend" \
    org.opencontainers.image.revision="${VCS_REF}" \
    org.opencontainers.image.version="${VCS_REF}"

# Expose API port
EXPOSE 3000

# Health check for Kubernetes
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD node healthcheck.js

CMD [ "node", "server.js" ]
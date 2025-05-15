# Multi-stage build for React + Express application

# Stage 1: Build React frontend
FROM node:16-alpine AS frontend-builder
WORKDIR /app
COPY src/frontend/package*.json ./
RUN npm ci
COPY src/frontend/ ./
RUN npm run build

# Stage 2: Production image with Express backend
FROM node:16-alpine AS production
WORKDIR /app

# Copy and install backend dependencies
COPY src/backend/package*.json ./
RUN npm ci --only=production

# Add metrics for Prometheus
RUN npm install prom-client

# Copy backend code
COPY src/backend/ ./

# Copy built frontend to the directory served by Express
# Typically Express serves static files from a "public" or "build" directory
COPY --from=frontend-builder /app/build ./public

# Set environment variable to production
ENV NODE_ENV=production

# Expose port
EXPOSE 8080

# Start Express server
CMD ["npm", "start"]
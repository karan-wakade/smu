FROM node:16-alpine AS builder

WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:16-alpine AS runner
WORKDIR /app

# Copy built assets from builder stage
COPY --from=builder /app/build ./build
COPY --from=builder /app/node_modules ./node_modules
COPY package*.json ./

# Install only production dependencies
RUN npm ci --only=production

# Add metrics for Prometheus
RUN npm install prom-client

# Expose port
EXPOSE 8080

# Start the app
CMD ["npm", "start"]
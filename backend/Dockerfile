FROM node:18-alpine
WORKDIR /app
COPY backend/package*.json ./
RUN npm ci
COPY backend/ ./
EXPOSE 3000
CMD ["node", "src/server.js"]
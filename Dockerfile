FROM node:20-alpine AS builder
WORKDIR /build

# Layer 1: dependencies (cached unless package.json changes)
COPY identity-ui/package.json identity-ui/package-lock.json ./
RUN npm ci

# Layer 2: source code + build
COPY identity-ui/ ./
RUN npm run build

FROM nginx:alpine
RUN addgroup -g 10001 -S appgroup && \
    adduser -u 10001 -S appuser -G appgroup
COPY --from=builder /build/dist /usr/share/nginx/html
COPY identity-ui/nginx.conf /etc/nginx/conf.d/default.conf
# nginx needs writable dirs for pid/cache — create them owned by appuser
RUN mkdir -p /var/cache/nginx /var/run && \
    chown -R 10001:10001 /var/cache/nginx /var/run /usr/share/nginx/html
USER 10001
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]

# ---- 第 1 阶段：安装依赖 ----
FROM node:20-alpine AS deps

# 启用 corepack 并使用稳定版本的 pnpm
RUN corepack enable && corepack prepare pnpm@8.15.4 --activate

WORKDIR /app

# 复制依赖相关文件
COPY package.json pnpm-lock.yaml* ./

# 智能安装策略：先尝试 frozen，失败则更新锁定文件
RUN if [ -f "pnpm-lock.yaml" ] && pnpm install --frozen-lockfile; then \
        echo "✅ Frozen lockfile installation successful"; \
    else \
        echo "🔄 Installing and generating new lockfile"; \
        pnpm install --no-frozen-lockfile; \
    fi

# ---- 第 2 阶段：构建项目 ----
FROM node:20-alpine AS builder

RUN corepack enable && corepack prepare pnpm@8.15.4 --activate

WORKDIR /app

# 复制依赖
COPY --from=deps /app/node_modules ./node_modules
# 复制源代码
COPY . .

# 设置构建环境
ENV DOCKER_ENV=true
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# 验证项目结构
RUN echo "🔍 Project verification:" && \
    [ -f "package.json" ] && echo "✅ package.json exists" || (echo "❌ package.json missing" && exit 1)

# 生成生产构建
RUN pnpm run build

# ---- 第 3 阶段：生成运行时镜像 ----
FROM node:20-alpine AS runner

# 为 ARMv7 安装必要的系统库
RUN apk add --no-cache \
    libc6-compat \
    ca-certificates

# 创建非 root 用户
RUN addgroup -g 1001 -S nodeS nodejs && \
    adduser -u 1001 -S nextjs -G nodejs

WORKDIR /app

# 设置生产环境变量
ENV NODE_ENV=production
ENV HOSTNAME=0.0.0.0
ENV PORT=3000
ENV DOCKER_ENV=true
ENV NEXT_TELEMETRY_DISABLED=1

# 从构建器复制必要文件
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/scripts ./scripts
COPY --from=builder --chown=nextjs:nodejs /app/start.js ./start.js
COPY --from=builder --chown=nextjs:nodejsnodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# 验证运行时文件完整性
RUN echo "📦 Runtime file check:" && \
    [ -f "start.js" ] && echo "✅ start.js ready" || echo "⚠️ start.js missing" && \
    [ -d "public" ] && echo "✅ public assets ready" || echo "⚠️ public assets missing"

# 切换到非特权用户
USER nextjs

EXPOSE 3000

# 健康检查
HEALTHCHECK --interval=30s --time --timeout=10s --start-period=40s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3000/api/health || exit 1

CMD ["node", "start.js"]

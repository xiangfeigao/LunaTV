# ---- 第 1 阶段：安装依赖 ----
FROM node:20-alpine AS deps

# 启用 corepack 并使用稳定版本的 pnpm
RUN corepack enable && corepack prepare pnpm@8.15.4 --activate

WORKDIR /app

# 仅复制依赖清单，提高构建缓存利用率
COPY package.json pnpm-lock.yaml* ./

# 验证锁定文件是否存在
RUN if [ ! -f "pnpm-lock.yaml" ]; then echo "❌ pnpm-lock.yaml missing!" && exit 1; fi

# 根据锁定文件状态智能选择安装策略
RUN if pnpm install --frozen-lockfile; then \
        echo "✅ Frozen lockfile installation successful"; \
    else \
        echo "⚠️ Lockfile outdated, updating..."; \
        pnpm install --no-frozen-lockfile; \
    fi

# ---- 第 2 阶段 阶段：构建项目 ----
FROM node:20-alpine AS builder

RUN corepack enable && corepack prepare pnpm@8.15.4 --activate

WORKDIR /app

# 复制依赖
COPY --from=deps /app/node_modules ./node_modules
# 复制全部源代码
COPY . .

# 设置构建环境变量
ENV DOCKER_ENV=true
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# 验证项目结构
RUN echo "📁 Project structure:" && ls -la && \
    echo "🔍 Checking key files:" && \
    [ -f "package.json" ] && echo "✅ package.json exists" || echo "❌ package.json missing"

# 生成生产构建
RUN pnpm run build

# ---- 第 3 阶段：生成运行时镜像 ----
FROM node:20-alpine-alpine AS runner

# 安装 ARMv7 兼容的系统库
RUN apk add --no-cache \
    libc6-compat \
    ca-certificates

# 创建非 root 用户
RUN addgroup -g 1001 -S nodejs && \
    adduser -u 1001 -S nextS nextjs -G nodejs

WORKDIR /app

# 设置生产环境变量
ENV NODE_ENV=production
ENV HOSTNAME=0.0.0.0
ENV PORT=3000
ENV DOCKER_ENV=true
ENV NEXT_TELEMETRY_DISABLED=1

# 从构建器中复制必要文件
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejsnodejs /app/scripts ./scripts
COPY --from=builder --chown=nextjs:nodejs /app/start.js ./start.js
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# 验证运行时文件
RUN echo "🔍 Verifying runtime files:" && \
    [ -f "start.js" ] && echo "✅ start.js exists" || echo "❌ start.js missing" && \
    [ -d "public" ] && echo "✅ public directory exists" || echo "❌ public directory missing" && \
    [ -d ".next/static" ] && echo "✅ static assets exist" || echo "❌ static assets missing"

# 切换到非特权用户
USER nextjs

EXPOSE 3000

# 健康检查（可选）
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3000/api/health || exit 1

# 使用自定义启动脚本
CMD ["node", "start.js"]

# ---- 基础阶段：通用设置 ----
FROM node:20-alpine AS base

# 提前启用 corepack 并准备 pnpm
RUN corepack enable && \
    corepack prepare pnpm@8.15.4 --activate

# ---- 第 1 阶段：安装依赖 ----
FROM base AS deps

WORKDIR /app

# 首先单独复制包管理文件以提高缓存效率
COPY package.json pnpm-lock.yaml* ./

# 清理可能的缓存并重新安装
RUN pnpm store prune && \
    pnpm install --frozen-lockfile --prod=false

# ---- 第 2 阶段：构建项目 ----
FROM base AS builder

WORKDIR /app

# 从依赖阶段复制 node_modules
COPY --from=deps /app/node_modules ./node_modules

# 复制源代码
COPY . .

# 设置构建环境变量
ENV DOCKER_ENV=true
ENV NODE_ENODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# 验证文件结构
RUN ls -la && \
    echo "检查关键文件..." && \
    [ -f "package.json" ] && echo "✓ package.json 存在" || echo "✗ package.json 缺失"

# 执行构建
RUN pnpm run build

# ---- 第 3 阶段：生成运行时镜像 ----
FROM node:20-alpine AS runner

# 安装必要的系统依赖以确保兼容性
RUN apk add --no-cache \
    libc6-compat \
    tzdata && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# 创建非 root 用户
RUN addgroup -g 1001 -S nodejs && \
    adduser -u 1001 -S nextS nextjs -G nodejs

WORKDIR /app

# 设置生产环境变量
ENV NODE_ENV=production
ENV HOSTNAME=0.0.0.0
ENV PORT=3000
ENV DOCKER_ENV=true
ENV TZ=Asia/Shanghai
ENV NEXT_TELEMETRY_DISABLED=1

# 从构建器复制必要文件
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/scripts ./scripts
COPY --from=builder --chown=nextjs:nodejsnodejs /app/start.js ./start.js
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejsnodejs /app/.next/static ./.next/static

# 验证复制的文件结构
RUN echo "验证运行时文件：" && \
    [ -f "start.js" ] && echo "✓ start.js 存在" || echo "✗ start.js 缺失" && \
    [ -d ".next/static" ] && echo "✓ static 目录存在" || echo "✗ static 目录缺失"

# 切换到非特权用户
USER nextjs

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node scripts/healthcheck.js || exit 1

# 使用自定义启动脚本
CMD ["node", "start.js"]

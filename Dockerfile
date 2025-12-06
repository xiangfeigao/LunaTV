# ---- 第 1 阶段 阶段：安装依赖 ----
FROM --platform=$BUILDPLATFORM node:20-alpine AS deps

# 启用 corepack 并激活 pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

WORKDIR /app

# 仅复制依赖文件以提高缓存效率
COPY package.json pnpm-lock.yaml ./

# 安装依赖（包括开发依赖以便于构建）
RUN pnpm install --frozen-lockfile

# ---- 第 2 阶段 阶段：构建项目 ----
FROM --platform=$BUILDPLATFORM node:20-alpine AS builder

# 启用 corepack 并激活 pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

WORKDIR /app

# 从依赖阶段复制 node_modules
COPY --from=deps /app/node_modules ./node_modules

# 复制源代码
COPY . .

# 设置环境变量以适配 Docker 构建
ENV DOCKER_ENV=true
ENV NEXT_TELEMETRY_DISABLED=1

# 执行构建
RUN pnpm run build

# ---- 第 3 阶段：生成运行时映像 ----
FROM node:20-alpine AS runner

# 安装必要的系统库以确保兼容性（例如针对某些 Node.js 原生模块）
RUN apk add --no-cache libc6-compat

# 创建非 root 用户以提高安全性
RUN addgroup -g 1001 -S nodejs && adduser -u 1001 -S nextjs -G nodejs nodejs

WORKDIR /app

# 设置生产环境变量
ENV NODE_ENV=production
ENV HOSTNAME=0.0.0.0
ENV PORT=3000
ENV DOCKER_ENV=true
ENV NEXT_TELEMETRY_DISABLED=1

# 从构建阶段复制必要文件并设置正确的所有权
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/scripts ./scripts
COPY --from=builder --chown=nextjs:nodejsnodejs /app/start.js ./start.js
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# 切换到非特权用户
USER nextjs

EXPOSE 3000

# 使用自定义启动脚本
CMD ["node", "start.js"]

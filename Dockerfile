# ---- 第 1 阶段：安装依赖 ----
FROM arm32v7/node:20-alpine AS deps

# 安装编译工具和系统依赖
RUN apk add --no-cache python3 make g++

# 启用 corepack 并激活 pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

WORKDIR /app

# 仅复制依赖清单
COPY package.json pnpm-lock.yaml ./

# 安装所有依赖
RUN pnpm install --frozen-lockfile

# ---- 第 2 阶段：构建项目 ----
FROM arm32v7/node:20-alpine AS builder

# 安装编译工具
RUN apk add --no-cache python3 make g++

RUN corepack enable && corepack prepare pnpm@latest --activate
WORKDIR /app

# 复制依赖
COPY --from=deps /app/node_modules ./node_modules
# 复制全部源代码
COPY . .

# 设置构建环境变量
ENV DOCKER_ENV=true
ENV NEXT_TELEMETRY_DISABLED=1
ENV NEXT_SWC_DISABLED=1  # 强制禁用 SWC

# 生成生产构建
RUN pnpm run build

# ---- 第 3 阶段：生成运行时镜像 ----
FROM arm32v7/node:20-alpine AS runner

# 创建非 root 用户
RUN addgroup -g 1001 -S nodejs && \
    adduser -u 1001 -S nextjs -G nodejs

WORKDIR /app
ENV NODE_ENV=production
ENV HOSTNAME=0.0.0.0
ENV PORT=3000
ENV DOCKER_ENV=true

# 从构建器中复制必要文件
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/scripts ./scripts
COPY --from=builder --chown=nextjs:nodejs /app/start.js ./start.js
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000
CMD ["node", "start.js"]

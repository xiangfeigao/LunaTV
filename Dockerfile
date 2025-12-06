# ---- 第1阶段：安装依赖 ----
FROM arm32v7/node:20-alpine AS deps

# 安装编译工具和系统依赖
RUN apk add --no-cache python3 make g++ git

WORKDIR /app

# 先复制依赖文件
COPY package.json pnpm-lock.yaml ./

# 启用 corepack 并安装指定版本的 pnpm
RUN corepack enable && \
    corepack prepare pnpm@8.15.7 --activate && \
    pnpm config set store-dir /app/.pnpm-store && \
    pnpm config set strict-peer-dependencies false && \
    pnpm install --frozen-lockfile --prod

# ---- 第2阶段：构建项目 ----
FROM arm32v7/node:20-alpine AS builder

# 安装编译工具
RUN apk add --no-cache python3 make g++

WORKDIR /app

# 从deps阶段复制node_modules
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/.pnpm-store /.pnpm-store

# 复制全部源代码
COPY . .

# 设置构建环境变量
ENV DOCKER_ENV=true
ENV NEXT_TELEMETRY_DISABLED=1
ENV NEXT_SWC_DISABLED=1

# 生成生产构建
RUN pnpm run build

# ---- 第3阶段：生成运行时镜像 ----
FROM arm32v7/node:20-alpine AS runner

# 创建非root用户
RUN addgroup -g 1001 -S nodejs && \
    adduser -u 1001 -S nextjs -G nodejs

WORKDIR /app
ENV NODE_ENV=production
ENV HOSTNAME=0.0.0.0
ENV PORT=3000
ENV DOCKER_ENV=true

# 从构建器复制必要文件
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/scripts ./scripts
COPY --from=builder --chown=nextjs:nodejs /app/start.js ./start.js
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# 设置用户和启动命令
USER nextjs
EXPOSE 3000
CMD ["node", "start.js"]

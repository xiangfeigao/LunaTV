# ---- 第1阶段：安装依赖 ----
FROM arm32v7/node:20-alpine AS deps

# 安装编译工具和系统依赖
RUN apk add --no-cache python3 make g++ git curl

WORKDIR /app

# 先复制依赖文件
COPY package.json pnpm-lock.yaml ./

# 设置国内镜像源并安装pnpm
RUN npm config set registry https://registry.npmmirror.com && \
    corepack enable && \
    corepack prepare pnpm@8.15.7 --activate && \
    pnpm config set store-dir /app/.pnpm-store && \
    pnpm config set strict-peer-dependencies false

# 安装依赖（增加重试机制）
RUN pnpm install --frozen-lockfile --prod || \
    (echo "第一次安装失败，重试..." && pnpm install --frozen-lockfile --prod)

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

# 安装开发依赖（用于构建）
RUN npm config set registry https://registry.npmmirror.com && \
    corepack enable && \
    corepack prepare pnpm@8.15.7 --activate && \
    pnpm install --frozen-lockfile

# 设置构建环境变量
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV NEXT_PUBLIC_ANALYTICS_ID=false

# 执行构建
RUN pnpm run build

# ---- 第3阶段：生成运行时镜像 ----
FROM arm32v7/node:20-alpine AS runner
RUN apk add --no-cache curl

WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000

# 从构建器复制必要文件
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public

# 设置非root用户
RUN addgroup -g 1001 -S nodejs && \
    adduser -u 1001 -S nextjs -G nodejs && \
    chown -R nextjs:nodejs /app

USER nextjs

EXPOSE 3000
CMD ["node", "server.js"]

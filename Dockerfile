ARG NODE_VERSION=18
FROM node:${NODE_VERSION}-bullseye-slim AS base
WORKDIR /app
ENV NODE_ENV=production

# 安装必需工具
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git \
  && rm -rf /var/lib/apt/lists/*

# 复制 package 文件以利用 Docker 缓存
COPY package.json pnpm-lock.yaml ./

# 设置 registry，启用 corepack 并激活指定 pnpm 版本，配置 pnpm
RUN set -eux; \
    npm config set registry https://registry.npmmirror.com; \
    corepack enable; \
    corepack prepare pnpm@8.15.7 --activate; \
    pnpm config set store-dir /app/.pnpm-store; \
    pnpm config set strict-peer-dependencies false; \
    pnpm -v || true

# deps 阶段：安装生产依赖（优先 frozen，失败则回退）
FROM base AS deps
WORKDIR /app
COPY package.json pnpm-lock.yaml ./

RUN set -eux; \
    echo "尝试使用 --frozen-lockfile 安装依赖..."; \
    if pnpm install --frozen-lockfile --prod; then \
      echo "pnpm install --frozen-lockfile 成功"; \
    else \
      echo "pnpm install --frozen-lockfile 失败，打印 lockfile 与 package.json 差异供排查："; \
      echo "---- package.json dependencies ----"; jq '.dependencies, .devDependencies' package.json || true; \
      echo "---- 尝试使用 --no-frozen-lockfile 回退安装 ----"; \
      pnpm install --no-frozen-lockfile --prod; \
    fi

# 如果需要构建步骤，使用 build 阶段（若无可跳过）
FROM base AS build
WORKDIR /app
# 将已安装的 node_modules 拷贝过来以加速构建
COPY --from=deps /app/node_modules ./node_modules
# 复制源码
COPY . .

# 仅在 package.json 中有 build 脚本时运行
RUN set -eux; \
    if node -e "process.exit(require('./package.json').scripts && require('./package.json').scripts.build ? 0 : 1)"; then \
      echo "检测到 build 脚本，执行 pnpm run build"; \
      pnpm run build; \
    else \
      echo "未检测到 build 脚本，跳过构建"; \
    fi

# 运行时镜像
FROM node:${NODE_VERSION}-bullseye-slim AS runner
WORKDIR /app
ENV NODE_ENV=production

# 安装必要运行时工具并激活 pnpm（如果需要运行 pnpm start）
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*; \
  npm config set registry https://registry.npmmirror.com; \
  corepack enable; \
  corepack prepare pnpm@8.15.7 --activate

# 拷贝 node_modules 与构建产物（按项目调整拷贝规则）
COPY --from=deps /app/node_modules ./node_modules
COPY --from=build /app ./

# 暴露端口（按需修改）
EXPOSE 3000

# 启动命令（根据 package.json 中的 start 脚本调整）
ENTRYPOINT ["pnpm", "start"]

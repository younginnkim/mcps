# ---- build stage ----
FROM node:20-alpine AS build
WORKDIR /app

# 의존성 먼저 설치 (레이어 캐시 활용)
COPY package.json package-lock.json ./
RUN npm ci

# 소스 복사 후 빌드
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# ---- runtime stage ----
FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8000

# 런타임 의존성만 설치
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# 빌드 산출물 복사
COPY --from=build /app/build ./build

EXPOSE 8000

# 비루트 사용자로 실행
USER node

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://localhost:'+(process.env.PORT||8000)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "build/index.js"]

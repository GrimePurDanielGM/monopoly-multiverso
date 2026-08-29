FROM node:22-alpine
WORKDIR /app
COPY package.json server.mjs ./
COPY lib ./lib
COPY public ./public
ENV PORT=8787 DATA_DIR=/data NODE_ENV=production
VOLUME /data
EXPOSE 8787
CMD ["node", "server.mjs"]

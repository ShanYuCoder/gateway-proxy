FROM node:24-alpine

WORKDIR /app

COPY package.json ./
RUN npm install

COPY server.js ./

EXPOSE 9325

CMD ["npm", "start"]

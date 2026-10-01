FROM node:24-alpine

WORKDIR /app

COPY package.json ./
RUN npm install

COPY index.js ./
COPY public ./public

EXPOSE 4000

CMD ["npm", "run", "dev"]

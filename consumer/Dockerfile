# Use robust Node.js slim image
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Install dependencies first for Docker caching
COPY package*.json ./
RUN npm install --production

# Copy the rest of the application
COPY . .

# Run the node app
CMD ["node", "index.js"]

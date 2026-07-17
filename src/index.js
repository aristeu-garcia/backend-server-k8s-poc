const express = require("express");

const promClient = require("prom-client");

const app = express();
const PORT = process.env.PORT || 3000;
promClient.collectDefaultMetrics();

app.use(express.json());

app.get("/metrics", (req, res) => {
  res.set("content-type", promClient.register.contentType);
  res.end(promClient.register.metrics());
});

app.get("/", (req, res) => {
  res.json({ message: "Hello from Express on Kubernetes!" });
});

app.get("/health", (req, res) => {
  res.status(200).json({ status: "ok", uptime: process.uptime() });
});

const items = [];

app.get("/items", (req, res) => {
  res.json(items);
});

app.post("/items", (req, res) => {
  const item = { id: items.length + 1, ...req.body };
  items.push(item);
  res.status(201).json(item);
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});

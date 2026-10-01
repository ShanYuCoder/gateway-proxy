const express = require('express');
const { SQSClient, ListQueuesCommand, ReceiveMessageCommand } = require('@aws-sdk/client-sqs');

const app = express();
const port = process.env.PORT || 9325;
const endpoint = process.env.SQS_ENDPOINT || 'http://localstack:4566';
const region = process.env.AWS_REGION || 'ap-southeast-1';

const sqs = new SQSClient({
  region,
  endpoint,
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID || 'test',
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || 'test'
  }
});

app.get('/api/queues', async (_req, res) => {
  try {
    const out = await sqs.send(new ListQueuesCommand({}));
    const queueUrls = out.QueueUrls || [];
    const queues = queueUrls.map((u) => ({
      url: u,
      name: u.split('/').pop() || u
    }));
    res.json({ queues });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/queues/:name/messages', async (req, res) => {
  try {
    const queueName = req.params.name;
    const queueUrl = `${endpoint}/000000000000/${queueName}`;
    const out = await sqs.send(new ReceiveMessageCommand({
      QueueUrl: queueUrl,
      MaxNumberOfMessages: Number(req.query.max || 10),
      WaitTimeSeconds: 1,
      VisibilityTimeout: 0,
      AttributeNames: ['All'],
      MessageAttributeNames: ['All']
    }));

    res.json({
      queueName,
      messages: out.Messages || []
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/', (_req, res) => {
  res.send(`<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>SQS UI</title>
  <style>
    body { font-family: ui-sans-serif, -apple-system, Segoe UI, sans-serif; margin: 24px; }
    h1 { margin-bottom: 8px; }
    .row { display: flex; gap: 16px; align-items: flex-start; }
    .card { border: 1px solid #ddd; border-radius: 8px; padding: 12px; flex: 1; }
    ul { list-style: none; padding: 0; margin: 0; }
    li { padding: 8px; border-bottom: 1px solid #eee; cursor: pointer; }
    li:hover { background: #f8f8f8; }
    pre { white-space: pre-wrap; word-break: break-word; background: #fafafa; padding: 10px; border-radius: 6px; }
    .muted { color: #666; font-size: 13px; }
  </style>
</head>
<body>
  <h1>SQS UI</h1>
  <div class="muted">Endpoint: ${endpoint}</div>
  <div class="row" style="margin-top:12px;">
    <div class="card">
      <h3>Queues</h3>
      <ul id="queues"></ul>
    </div>
    <div class="card">
      <h3>Messages</h3>
      <div id="messages" class="muted">Select a queue</div>
    </div>
  </div>

  <script>
    const queuesEl = document.getElementById('queues');
    const messagesEl = document.getElementById('messages');

    async function loadQueues() {
      const res = await fetch('/api/queues');
      const data = await res.json();
      const queues = data.queues || [];
      queuesEl.innerHTML = queues.map(q => `<li data-name="${q.name}">${q.name}</li>`).join('') || '<li>No queues</li>';

      document.querySelectorAll('#queues li[data-name]').forEach((el) => {
        el.addEventListener('click', () => loadMessages(el.dataset.name));
      });
    }

    async function loadMessages(queueName) {
      messagesEl.innerHTML = 'Loading...';
      const res = await fetch(`/api/queues/${queueName}/messages`);
      const data = await res.json();
      const msgs = data.messages || [];
      if (!msgs.length) {
        messagesEl.innerHTML = `<div class="muted">No messages in ${queueName}</div>`;
        return;
      }
      messagesEl.innerHTML = msgs.map((m) => `<pre>${JSON.stringify(m, null, 2)}</pre>`).join('');
    }

    loadQueues();
  </script>
</body>
</html>`);
});

app.listen(port, () => {
  console.log(`sqs-ui listening on port ${port}`);
});

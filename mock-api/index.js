const express = require('express');
const bodyParser = require('body-parser');
const fs = require('fs');
const path = require('path');

const app = express();

app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

app.use((req, _res, next) => {
  if (req.path === '/send-sms' || req.path.startsWith('/sms')) return next();
  console.log('[REQUEST]', req.method, req.path);
  next();
});

const smsLogFile = '/data/sms.log';

function pickSmsPayload(body, query) {
  const b = body || {};
  const q = query || {};
  const phone = b.phoneNumber || b.phone || b.to || b.recipient || b.mobile
    || q.phoneNumber || q.phone || q.to || q.recipient || q.mobile || '';
  const message = b.message || b.content || b.text || b.body || b.msg
    || q.message || q.content || q.text || q.body || q.msg || '';
  return { phoneNumber: phone, message };
}

function handleSendSms(req, res) {
  console.log('[SMS]', req.method, req.url, 'body:', JSON.stringify(req.body), 'query:', JSON.stringify(req.query));

  const { phoneNumber, message } = pickSmsPayload(req.body, req.query);
  const sms = {
    phoneNumber,
    message,
    timestamp: new Date().toISOString(),
    rawBody: Object.keys(req.body || {}).length ? req.body : undefined
  };

  try {
    fs.appendFileSync(smsLogFile, JSON.stringify(sms) + '\n');
  } catch (e) {
    console.error('[SMS] Failed to write log:', e.message);
  }

  res.json({
    responseCode: 0,
    responseMessage: 'SMS received'
  });
}

app.post('/send-sms', handleSendSms);
app.get('/send-sms', handleSendSms);

app.get('/sms/status', (_req, res) => {
  res.json({
    responseCode: 0,
    responseMessage: 'OK'
  });
});

app.get('/sms/inbox', (_req, res) => {
  let logs = [];
  if (fs.existsSync(smsLogFile)) {
    const lines = fs.readFileSync(smsLogFile, 'utf-8').split('\n').filter(Boolean);
    for (const line of lines) {
      try {
        logs.push(JSON.parse(line));
      } catch (_) {
        logs.push({ raw: line });
      }
    }
  }
  res.json(logs);
});

const slackLogFile = '/data/slack.log';

app.post('/slack/webhook', (req, res) => {
  const item = {
    timestamp: new Date().toISOString(),
    body: req.body
  };

  fs.appendFileSync(slackLogFile, JSON.stringify(item) + '\n');

  res.json({ ok: true });
});

app.get('/slack/inbox', (_req, res) => {
  const logs = fs.existsSync(slackLogFile)
    ? fs.readFileSync(slackLogFile, 'utf8')
      .split('\n')
      .filter(Boolean)
      .map(JSON.parse)
    : [];

  res.json(logs);
});

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'mock-api' });
});

app.get('/api/meta', (_req, res) => {
  res.json({
    service: 'mock-api',
    endpoints: {
      'POST/GET /send-sms': 'send SMS',
      'GET /sms/inbox': 'list SMS',
      'GET /sms/status': 'status',
      'POST /slack/webhook': 'send Slack',
      'GET /slack/inbox': 'list Slack'
    }
  });
});

const publicDir = path.join(__dirname, 'public');

app.get('/', (_req, res) => {
  res.sendFile(path.join(publicDir, 'index.html'));
});

app.use(express.static(publicDir, { index: false }));

const port = process.env.PORT || 4000;
app.listen(port, () => console.log(`Mock hub + API on port ${port}`));

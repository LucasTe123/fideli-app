const http = require('node:http');
const http2 = require('node:http2');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const envFile = path.join(__dirname, '.env');
if (fs.existsSync(envFile)) {
  for (const line of fs.readFileSync(envFile, 'utf8').split(/\r?\n/)) {
    const match = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (match && process.env[match[1]] === undefined) {
      process.env[match[1]] = match[2].trim();
    }
  }
}

const port = Number(process.env.PORT || 8787);
const host = process.env.HOST || '0.0.0.0';
const root = __dirname;
const dataDirectory = path.join(root, 'data');
const storePath = process.env.STORE_PATH || path.join(dataDirectory, 'store.json');
let store = { customers: {}, registrations: {}, updated: {} };

if (fs.existsSync(storePath)) {
  try {
    store = { ...store, ...JSON.parse(fs.readFileSync(storePath, 'utf8')) };
  } catch (error) {
    console.error('No se pudo leer el almacenamiento local:', error.message);
  }
}

function saveStore() {
  fs.mkdirSync(path.dirname(storePath), { recursive: true });
  const temporary = `${storePath}.tmp`;
  fs.writeFileSync(temporary, JSON.stringify(store, null, 2));
  fs.renameSync(temporary, storePath);
}

function json(res, status, body) {
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'access-control-allow-origin': '*',
  });
  res.end(JSON.stringify(body));
}

function value(url, key, fallback = '') {
  return String(url.searchParams.get(key) || fallback).slice(0, 160);
}

function customerFrom(url, id) {
  const safeId = id.replace(/[^a-zA-Z0-9._-]/g, '-').slice(0, 80);
  return {
    id: safeId,
    name: value(url, 'name', 'Cliente Fideli'),
    points: Math.max(0, Number(value(url, 'points', '0')) || 0),
    stamps: Math.max(0, Number(value(url, 'stamps', '0')) || 0),
    visits: Math.max(0, Number(value(url, 'visits', '0')) || 0),
    tier: value(url, 'tier', 'Bronce'),
    referral: value(url, 'referral', safeId),
    business: value(url, 'business', 'Fideli'),
    color: /^#[0-9a-fA-F]{6}$/.test(value(url, 'color')) ? value(url, 'color') : '#6750A4',
  };
}

function normalizeCustomer(input, id) {
  const safeId = String(id || input.id || '').replace(/[^a-zA-Z0-9._-]/g, '-').slice(0, 80);
  const text = (key, fallback) => String(input[key] ?? fallback).slice(0, 160);
  const number = (key) => Math.max(0, Number(input[key]) || 0);
  return {
    id: safeId,
    name: text('name', 'Cliente Fideli'),
    points: number('points'),
    stamps: number('stamps'),
    visits: number('visits'),
    tier: text('tier', 'Bronce'),
    referral: text('referral', safeId),
    business: text('business', 'Fideli'),
    color: /^#[0-9a-fA-F]{6}$/.test(text('color', '')) ? text('color', '') : '#6750A4',
  };
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > 1024 * 1024) {
        reject(new Error('Solicitud demasiado grande'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      try {
        resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {});
      } catch (error) {
        reject(error);
      }
    });
    req.on('error', reject);
  });
}

function passToken(serialNumber) {
  return crypto.createHash('sha256').update(`${serialNumber}:${process.env.APPLE_TEAM_ID}`).digest('hex');
}

function authorized(req, serialNumber) {
  return req.headers.authorization === `ApplePass ${passToken(serialNumber)}`;
}

function appleConfigured() {
  const fileKeys = ['APPLE_CERT_PATH', 'APPLE_KEY_PATH', 'APPLE_WWDR_PATH'];
  return Boolean(
    process.env.APPLE_PASS_TYPE_ID &&
    process.env.APPLE_TEAM_ID &&
    fileKeys.every((key) => process.env[key] && fs.existsSync(process.env[key])),
  );
}

function googleConfigured() {
  return Boolean(
    process.env.GOOGLE_ISSUER_ID &&
    process.env.GOOGLE_SERVICE_ACCOUNT_PATH &&
    process.env.GOOGLE_LOGO_URL &&
    fs.existsSync(process.env.GOOGLE_SERVICE_ACCOUNT_PATH),
  );
}

function applePassJson(customer) {
  const publicUrl = process.env.PUBLIC_BASE_URL;
  const authenticationToken = passToken(customer.id);
  const goal = 7;
  const remaining = Math.max(0, goal - customer.stamps);
  const pass = {
    formatVersion: 1,
    passTypeIdentifier: process.env.APPLE_PASS_TYPE_ID,
    serialNumber: customer.id,
    teamIdentifier: process.env.APPLE_TEAM_ID,
    organizationName: customer.business,
    description: `Tarjeta de fidelidad de ${customer.business}`,
    logoText: customer.business,
    foregroundColor: 'rgb(255, 255, 255)',
    labelColor: 'rgb(255, 255, 255)',
    backgroundColor: hexToRgb(customer.color),
    storeCard: {
      headerFields: [{ key: 'reward', label: 'RECOMPENSA', value: remaining === 0 ? 'LISTA' : `FALTAN ${remaining}` }],
      primaryFields: [{ key: 'stamps', label: 'SELLOS', value: `${customer.stamps} / ${goal}` }],
      secondaryFields: [
        { key: 'member', label: 'CLIENTE', value: customer.name },
        { key: 'visits', label: 'VISITAS', value: customer.visits },
      ],
      auxiliaryFields: [{ key: 'code', label: 'CÓDIGO', value: customer.referral }],
      backFields: [
        { key: 'benefit', label: 'Tu recompensa', value: 'Completa 7 sellos para obtener un producto de cortesía.' },
        { key: 'terms', label: 'Cómo usarla', value: 'Presenta este pase en el comercio. El vendedor escaneará el QR y registrará tu sello y visita.' },
      ],
    },
    barcode: {
      format: 'PKBarcodeFormatQR',
      message: `fideli://customer/${customer.id}?ref=${encodeURIComponent(customer.referral)}`,
      messageEncoding: 'iso-8859-1',
      altText: customer.referral,
    },
  };
  if (publicUrl) {
    pass.webServiceURL = publicUrl.replace(/\/$/, '');
    pass.authenticationToken = authenticationToken;
  }
  const latitude = Number(process.env.STORE_LATITUDE);
  const longitude = Number(process.env.STORE_LONGITUDE);
  if (Number.isFinite(latitude) && Number.isFinite(longitude)) {
    pass.locations = [{
      latitude,
      longitude,
      relevantText: process.env.STORE_RELEVANT_TEXT || `Estás cerca de ${customer.business}. Presenta tu tarjeta Fideli.`,
    }];
  }
  return pass;
}

function hexToRgb(hex) {
  const clean = hex.replace('#', '');
  const parts = [0, 2, 4].map((start) => parseInt(clean.slice(start, start + 2), 16));
  return `rgb(${parts[0]}, ${parts[1]}, ${parts[2]})`;
}

function createApplePass(customer) {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fideli-pass-'));
  const output = path.join(tempDir, `${customer.id}.pkpass`);
  try {
    const passDir = path.join(tempDir, 'pass');
    fs.mkdirSync(passDir);
    fs.writeFileSync(path.join(passDir, 'pass.json'), JSON.stringify(applePassJson(customer), null, 2));
    fs.copyFileSync(path.join(root, 'assets', 'icon.png'), path.join(passDir, 'icon.png'));
    fs.copyFileSync(path.join(root, 'assets', 'icon@2x.png'), path.join(passDir, 'icon@2x.png'));

    const manifest = {};
    for (const file of fs.readdirSync(passDir)) {
      const contents = fs.readFileSync(path.join(passDir, file));
      manifest[file] = crypto.createHash('sha1').update(contents).digest('hex');
    }
    fs.writeFileSync(path.join(passDir, 'manifest.json'), JSON.stringify(manifest));
    execFileSync('openssl', [
      'smime', '-binary', '-sign',
      '-certfile', process.env.APPLE_WWDR_PATH,
      '-signer', process.env.APPLE_CERT_PATH,
      '-inkey', process.env.APPLE_KEY_PATH,
      '-in', path.join(passDir, 'manifest.json'),
      '-out', path.join(passDir, 'signature'),
      '-outform', 'DER',
    ]);
    execFileSync('zip', ['-q', '-r', output, '.'], { cwd: passDir });
    return fs.readFileSync(output);
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

function base64Url(input) {
  const bytes = Buffer.isBuffer(input) ? input : Buffer.from(JSON.stringify(input));
  return bytes.toString('base64url');
}

function googleSaveUrl(customer) {
  const credentials = JSON.parse(fs.readFileSync(process.env.GOOGLE_SERVICE_ACCOUNT_PATH, 'utf8'));
  const issuerId = process.env.GOOGLE_ISSUER_ID;
  const classSuffix = process.env.GOOGLE_CLASS_SUFFIX || 'fideli_loyalty';
  const classId = `${issuerId}.${classSuffix}`;
  const objectId = `${issuerId}.${customer.id}`;
  const now = Math.floor(Date.now() / 1000);
  const logoUrl = process.env.GOOGLE_LOGO_URL;
  const claims = {
    iss: credentials.client_email,
    aud: 'google',
    origins: [new URL(logoUrl).origin],
    typ: 'savetowallet',
    iat: now,
    payload: {
      loyaltyClasses: [{
        id: classId,
        issuerName: customer.business,
        programName: `Club ${customer.business}`,
        reviewStatus: 'UNDER_REVIEW',
        hexBackgroundColor: customer.color,
        programLogo: {
          sourceUri: { uri: logoUrl },
          contentDescription: {
            defaultValue: { language: 'es', value: `Logo de ${customer.business}` },
          },
        },
      }],
      loyaltyObjects: [{
        id: objectId,
        classId,
        state: 'ACTIVE',
        accountId: customer.id,
        accountName: customer.name,
        loyaltyPoints: { label: 'Puntos', balance: { int: customer.points } },
        barcode: { type: 'QR_CODE', value: `fideli://customer/${customer.id}?ref=${customer.referral}`, alternateText: customer.referral },
        textModulesData: [
          { id: 'tier', header: 'Nivel', body: customer.tier },
          { id: 'visits', header: 'Visitas', body: String(customer.visits) },
        ],
      }],
    },
  };
  const header = { alg: 'RS256', typ: 'JWT' };
  const unsigned = `${base64Url(header)}.${base64Url(claims)}`;
  const signature = crypto.sign('RSA-SHA256', Buffer.from(unsigned), credentials.private_key);
  return `https://pay.google.com/gp/v/save/${unsigned}.${base64Url(signature)}`;
}

function registrationKey(device, serial) {
  return `${device}:${serial}`;
}

async function notifyWallet(serialNumber) {
  if (!appleConfigured()) return [];
  const registrations = Object.values(store.registrations)
    .filter((item) => item.serialNumber === serialNumber);
  if (registrations.length === 0) return [];
  const client = http2.connect('https://api.push.apple.com', {
    cert: fs.readFileSync(process.env.APPLE_CERT_PATH),
    key: fs.readFileSync(process.env.APPLE_KEY_PATH),
  });
  const results = [];
  try {
    for (const registration of registrations) {
      results.push(await new Promise((resolve) => {
        const request = client.request({
          ':method': 'POST',
          ':path': `/3/device/${registration.pushToken}`,
          'apns-topic': process.env.APPLE_PASS_TYPE_ID,
          'apns-push-type': 'background',
          'apns-priority': '5',
        });
        let status = 0;
        request.on('response', (headers) => { status = Number(headers[':status'] || 0); });
        request.on('error', (error) => resolve({ ok: false, error: error.message }));
        request.on('end', () => resolve({ ok: status === 200, status }));
        request.end('{}');
      }));
    }
  } finally {
    client.close();
  }
  return results;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'access-control-allow-origin': '*',
      'access-control-allow-methods': 'GET, POST, DELETE, OPTIONS',
      'access-control-allow-headers': 'content-type, authorization',
    });
    return res.end();
  }
  if (req.method === 'GET' && url.pathname === '/health') {
    const apple = appleConfigured();
    const google = googleConfigured();
    return json(res, 200, { ok: true, mode: apple || google ? 'real' : 'demo', apple, google });
  }
  if (req.method === 'GET' && url.pathname === '/assets/icon.png') {
    res.writeHead(200, { 'content-type': 'image/png', 'cache-control': 'public, max-age=86400' });
    return fs.createReadStream(path.join(root, 'assets', 'icon@2x.png')).pipe(res);
  }
  const customerMatch = url.pathname.match(/^\/api\/customers\/([^/]+)$/);
  if (req.method === 'POST' && customerMatch) {
    try {
      const id = decodeURIComponent(customerMatch[1]);
      const customer = normalizeCustomer(await readJson(req), id);
      store.customers[customer.id] = customer;
      store.updated[customer.id] = Date.now();
      saveStore();
      const pushes = await notifyWallet(customer.id);
      return json(res, 200, {
        ok: true,
        customer,
        walletUpdateRequested: pushes.some((item) => item.ok),
        registeredDevices: pushes.length,
      });
    } catch (error) {
      console.error(error);
      return json(res, 400, { message: 'No se pudo guardar el cliente.' });
    }
  }

  const registrationMatch = url.pathname.match(/^\/v1\/devices\/([^/]+)\/registrations\/([^/]+)\/([^/]+)$/);
  if (registrationMatch) {
    const [, device, passType, serial] = registrationMatch.map(decodeURIComponent);
    if (passType !== process.env.APPLE_PASS_TYPE_ID || !authorized(req, serial)) {
      return json(res, 401, { message: 'No autorizado' });
    }
    const key = registrationKey(device, serial);
    if (req.method === 'POST') {
      try {
        const body = await readJson(req);
        if (!body.pushToken) return json(res, 400, { message: 'pushToken requerido' });
        const isNew = !store.registrations[key];
        store.registrations[key] = { deviceLibraryIdentifier: device, passTypeIdentifier: passType, serialNumber: serial, pushToken: String(body.pushToken) };
        saveStore();
        res.writeHead(isNew ? 201 : 200);
        return res.end();
      } catch (error) {
        return json(res, 400, { message: 'Registro inválido' });
      }
    }
    if (req.method === 'DELETE') {
      delete store.registrations[key];
      saveStore();
      res.writeHead(200);
      return res.end();
    }
  }

  const registrationsMatch = url.pathname.match(/^\/v1\/devices\/([^/]+)\/registrations\/([^/]+)$/);
  if (req.method === 'GET' && registrationsMatch) {
    const [, device, passType] = registrationsMatch.map(decodeURIComponent);
    const since = Number(url.searchParams.get('passesUpdatedSince') || 0);
    const serialNumbers = Object.values(store.registrations)
      .filter((item) => item.deviceLibraryIdentifier === device && item.passTypeIdentifier === passType)
      .map((item) => item.serialNumber)
      .filter((serial) => Number(store.updated[serial] || 0) > since);
    if (serialNumbers.length === 0) {
      res.writeHead(204);
      return res.end();
    }
    const lastUpdated = Math.max(...serialNumbers.map((serial) => Number(store.updated[serial] || 0)));
    return json(res, 200, { serialNumbers, lastUpdated: String(lastUpdated) });
  }

  const updatedPassMatch = url.pathname.match(/^\/v1\/passes\/([^/]+)\/([^/]+)$/);
  if (req.method === 'GET' && updatedPassMatch) {
    const [, passType, serial] = updatedPassMatch.map(decodeURIComponent);
    if (passType !== process.env.APPLE_PASS_TYPE_ID || !authorized(req, serial)) {
      return json(res, 401, { message: 'No autorizado' });
    }
    const customer = store.customers[serial];
    if (!customer) return json(res, 404, { message: 'Cliente no encontrado' });
    try {
      const pass = createApplePass(customer);
      res.writeHead(200, {
        'content-type': 'application/vnd.apple.pkpass',
        'last-modified': new Date(store.updated[serial] || Date.now()).toUTCString(),
      });
      return res.end(pass);
    } catch (error) {
      console.error(error);
      return json(res, 500, { message: 'No se pudo actualizar el pase' });
    }
  }

  if (req.method === 'POST' && url.pathname === '/v1/log') {
    try {
      const body = await readJson(req);
      console.log('Apple Wallet:', body.logs || body);
    } catch (_) { /* Apple no necesita una respuesta JSON. */ }
    res.writeHead(200);
    return res.end();
  }

  const match = url.pathname.match(/^\/api\/wallet\/(apple|google)\/([^/]+)$/);
  if (req.method === 'GET' && match) {
    const [, platform, id] = match;
    const queryCustomer = customerFrom(url, decodeURIComponent(id));
    const customer = Object.keys(Object.fromEntries(url.searchParams)).length > 0
      ? queryCustomer
      : (store.customers[queryCustomer.id] || queryCustomer);
    try {
      if (platform === 'apple') {
        if (!appleConfigured()) return json(res, 503, { demoMode: true, message: 'Modo demo: agrega los certificados Apple al backend para firmar un .pkpass real.' });
        store.customers[customer.id] = customer;
        store.updated[customer.id] = store.updated[customer.id] || Date.now();
        saveStore();
        const pass = createApplePass(customer);
        res.writeHead(200, { 'content-type': 'application/vnd.apple.pkpass', 'content-disposition': `attachment; filename="${customer.id}.pkpass"` });
        return res.end(pass);
      }
      if (!googleConfigured()) return json(res, 503, { demoMode: true, message: 'Modo demo: configura Issuer ID y Service Account para crear el enlace de Google Wallet.' });
      return json(res, 200, { saveUrl: googleSaveUrl(customer) });
    } catch (error) {
      console.error(error);
      return json(res, 500, { message: 'No se pudo generar el pase. Revisa credenciales y configuración del backend.' });
    }
  }
  return json(res, 404, { message: 'Ruta no encontrada' });
});

if (require.main === module) {
  server.listen(port, host, () => {
    console.log(`Fideli Wallet Service: http://${host}:${port}`);
    console.log(`Apple: ${appleConfigured() ? 'real' : 'demo'} | Google: ${googleConfigured() ? 'real' : 'demo'}`);
  });
}

module.exports = { applePassJson, customerFrom, normalizeCustomer, googleSaveUrl, hexToRgb, passToken };

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { applePassJson, customerFrom, googleSaveUrl, hexToRgb } = require('./server');

test('convierte color hexadecimal al formato de Wallet', () => {
  assert.equal(hexToRgb('#6750A4'), 'rgb(103, 80, 164)');
});

test('normaliza parámetros del cliente', () => {
  const url = new URL('http://localhost/?name=Ana&points=120&tier=Plata&color=%236750A4');
  const customer = customerFrom(url, 'customer-1');
  assert.equal(customer.name, 'Ana');
  assert.equal(customer.points, 120);
  assert.equal(customer.color, '#6750A4');
});

test('genera la estructura storeCard y QR', () => {
  process.env.APPLE_PASS_TYPE_ID = 'pass.test.fideli';
  process.env.APPLE_TEAM_ID = 'TEAM123';
  const pass = applePassJson({
    id: 'c1', name: 'Ana', points: 120, stamps: 2, visits: 4,
    tier: 'Plata', referral: 'ANA1234', business: 'Café', color: '#6750A4',
  });
  assert.equal(pass.storeCard.primaryFields[0].value, '2 / 7');
  assert.equal(pass.storeCard.primaryFields[0].label, 'SELLOS');
  assert.match(pass.barcode.message, /^fideli:\/\/customer\/c1/);
});

test('firma un JWT RS256 válido para Google Wallet', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'fideli-google-test-'));
  try {
    const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', {
      modulusLength: 2048,
      privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
      publicKeyEncoding: { type: 'spki', format: 'pem' },
    });
    const credentialsPath = path.join(directory, 'service-account.json');
    fs.writeFileSync(credentialsPath, JSON.stringify({ client_email: 'wallet@example.test', private_key: privateKey }));
    process.env.GOOGLE_SERVICE_ACCOUNT_PATH = credentialsPath;
    process.env.GOOGLE_ISSUER_ID = '123456789';
    process.env.GOOGLE_CLASS_SUFFIX = 'fideli';
    process.env.GOOGLE_LOGO_URL = 'https://wallet.example.test/assets/icon.png';
    const url = googleSaveUrl({
      id: 'c1', name: 'Ana', points: 120, stamps: 2, visits: 4,
      tier: 'Plata', referral: 'ANA1234', business: 'Café', color: '#6750A4',
    });
    const token = url.split('/').pop();
    const [header, claims, signature] = token.split('.');
    const unsigned = `${header}.${claims}`;
    assert.equal(
      crypto.verify('RSA-SHA256', Buffer.from(unsigned), publicKey, Buffer.from(signature, 'base64url')),
      true,
    );
    const payload = JSON.parse(Buffer.from(claims, 'base64url').toString('utf8'));
    assert.equal(payload.payload.loyaltyObjects[0].loyaltyPoints.balance.int, 120);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

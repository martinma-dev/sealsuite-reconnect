#!/usr/bin/env node
'use strict';

const childProcess = require('child_process');
const fs = require('fs');
const http2 = require('http2');
const os = require('os');
const path = require('path');

const HOME = os.homedir();
const STATE_DIR =
  process.env.SEALSUITE_RECONNECT_STATE_DIR ||
  path.join(HOME, 'Library/Application Support/SealSuiteReconnect');
const RPC_CONF = '/usr/local/corplink/rpc.conf';
const PORT_CACHE = path.join(STATE_DIR, 'grpc-port');
const CONNECT_CONFIG = path.join(STATE_DIR, 'vpn-connect.json');

const STATUS_NAMES = {
  0: 'Disconnected',
  1: 'Connecting',
  2: 'Connected',
  3: 'Disconnecting',
  4: 'Reasserting',
};

function timestamp() {
  const now = new Date();
  const pad = (value) => String(value).padStart(2, '0');
  return [
    now.getFullYear(),
    pad(now.getMonth() + 1),
    pad(now.getDate()),
  ].join('-') + ' ' + [
    pad(now.getHours()),
    pad(now.getMinutes()),
    pad(now.getSeconds()),
  ].join(':');
}

function log(message) {
  console.log(`${timestamp()} grpc ${message}`);
}

function die(message) {
  console.error(`${timestamp()} grpc error: ${message}`);
  process.exit(1);
}

function readToken() {
  const token = fs.readFileSync(RPC_CONF, 'utf8').trim();
  if (!token) {
    throw new Error(`${RPC_CONF} is empty`);
  }
  return token;
}

function currentUser() {
  try {
    return os.userInfo().username || process.env.USER || 'martin';
  } catch (_) {
    return process.env.USER || 'martin';
  }
}

function readConnectConfig() {
  const defaults = {
    server: -1,
    mode: 'Split',
  };

  if (!fs.existsSync(CONNECT_CONFIG)) {
    return defaults;
  }

  const parsed = JSON.parse(fs.readFileSync(CONNECT_CONFIG, 'utf8'));
  const config = {
    ...defaults,
    ...parsed,
  };

  if (!Number.isInteger(config.server)) {
    throw new Error(`${CONNECT_CONFIG}: server must be an integer`);
  }
  if (typeof config.mode !== 'string' || !config.mode) {
    throw new Error(`${CONNECT_CONFIG}: mode must be a non-empty string`);
  }
  if (config.exportId !== undefined && !Number.isInteger(config.exportId)) {
    throw new Error(`${CONNECT_CONFIG}: exportId must be an integer`);
  }
  if (config.zone !== undefined && typeof config.zone !== 'string') {
    throw new Error(`${CONNECT_CONFIG}: zone must be a string`);
  }
  if (config.otp !== undefined && typeof config.otp !== 'string') {
    throw new Error(`${CONNECT_CONFIG}: otp must be a string`);
  }

  return config;
}

function uniqueNumbers(values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    const number = Number(value);
    if (!Number.isInteger(number) || number <= 0 || number > 65535 || seen.has(number)) {
      continue;
    }
    seen.add(number);
    result.push(number);
  }
  return result;
}

function cachedPort() {
  try {
    const value = fs.readFileSync(PORT_CACHE, 'utf8').trim();
    return Number.parseInt(value, 10);
  } catch (_) {
    return 0;
  }
}

function cachePort(port) {
  try {
    fs.mkdirSync(STATE_DIR, { recursive: true });
    fs.writeFileSync(PORT_CACHE, `${port}\n`);
  } catch (_) {
    // Caching is best-effort; reconnect should still work without it.
  }
}

function lsofOutput() {
  const candidates = ['/usr/sbin/lsof', '/usr/bin/lsof', 'lsof'];
  for (const command of candidates) {
    try {
      return childProcess.execFileSync(
        command,
        ['-nP', '-iTCP', '-sTCP:ESTABLISHED'],
        {
          encoding: 'utf8',
          timeout: 5000,
        },
      );
    } catch (_) {
      // Try the next executable name/path.
    }
  }
  return '';
}

function candidatePortsFromLsof() {
  const ports = [];
  const lines = lsofOutput().split(/\r?\n/);
  for (const line of lines) {
    if (!/SealSuite|Corplink/i.test(line)) {
      continue;
    }
    const match = line.match(/->127\.0\.0\.1:(\d+)\s+\(ESTABLISHED\)/);
    if (match) {
      ports.push(Number.parseInt(match[1], 10));
    }
  }
  return ports;
}

function candidatePorts() {
  return uniqueNumbers([
    cachedPort(),
    ...candidatePortsFromLsof(),
    31055,
    31056,
  ]);
}

function encodeVarint(value) {
  let current = BigInt(value);
  const bytes = [];
  do {
    let byte = Number(current & 0x7fn);
    current >>= 7n;
    if (current !== 0n) {
      byte |= 0x80;
    }
    bytes.push(byte);
  } while (current !== 0n);
  return Buffer.from(bytes);
}

function encodeSignedInt32(value) {
  if (value >= 0) {
    return encodeVarint(value);
  }
  return encodeVarint(BigInt.asUintN(64, BigInt(value)));
}

function encodeFieldKey(fieldNumber, wireType) {
  return encodeVarint((BigInt(fieldNumber) << 3n) | BigInt(wireType));
}

function encodeInt32Field(fieldNumber, value) {
  return Buffer.concat([encodeFieldKey(fieldNumber, 0), encodeSignedInt32(value)]);
}

function encodeStringField(fieldNumber, value) {
  const payload = Buffer.from(value, 'utf8');
  return Buffer.concat([encodeFieldKey(fieldNumber, 2), encodeVarint(payload.length), payload]);
}

function encodeConnectRequest(config) {
  const fields = [
    encodeInt32Field(1, config.server),
    encodeStringField(2, config.mode),
  ];

  if (config.otp) {
    fields.push(encodeStringField(3, config.otp));
  }
  if (config.zone) {
    fields.push(encodeStringField(4, config.zone));
  }
  if (config.exportId !== undefined) {
    fields.push(encodeInt32Field(5, config.exportId));
  }

  return Buffer.concat(fields);
}

function readVarint(buffer, offset) {
  let result = 0n;
  let shift = 0n;
  let cursor = offset;

  while (cursor < buffer.length) {
    const byte = buffer[cursor++];
    result |= BigInt(byte & 0x7f) << shift;
    if ((byte & 0x80) === 0) {
      return { value: result, offset: cursor };
    }
    shift += 7n;
    if (shift > 70n) {
      break;
    }
  }

  throw new Error('invalid protobuf varint');
}

function decodeFields(buffer) {
  const fields = [];
  let offset = 0;

  while (offset < buffer.length) {
    const key = readVarint(buffer, offset);
    offset = key.offset;
    const fieldNumber = Number(key.value >> 3n);
    const wireType = Number(key.value & 0x07n);

    if (fieldNumber <= 0) {
      break;
    }

    if (wireType === 0) {
      const value = readVarint(buffer, offset);
      offset = value.offset;
      fields.push({ fieldNumber, wireType, value: value.value });
      continue;
    }

    if (wireType === 1) {
      if (offset + 8 > buffer.length) {
        throw new Error('invalid protobuf fixed64 field');
      }
      fields.push({ fieldNumber, wireType, value: buffer.subarray(offset, offset + 8) });
      offset += 8;
      continue;
    }

    if (wireType === 2) {
      const length = readVarint(buffer, offset);
      offset = length.offset;
      const end = offset + Number(length.value);
      if (end > buffer.length) {
        throw new Error('invalid protobuf length-delimited field');
      }
      const bytes = buffer.subarray(offset, end);
      fields.push({ fieldNumber, wireType, bytes, text: printableText(bytes) });
      offset = end;
      continue;
    }

    if (wireType === 5) {
      if (offset + 4 > buffer.length) {
        throw new Error('invalid protobuf fixed32 field');
      }
      fields.push({ fieldNumber, wireType, value: buffer.subarray(offset, offset + 4) });
      offset += 4;
      continue;
    }

    throw new Error(`unsupported protobuf wire type ${wireType}`);
  }

  return fields;
}

function printableText(buffer) {
  if (buffer.length === 0) {
    return '';
  }
  const text = buffer.toString('utf8');
  if (text.includes('\u0000')) {
    return '';
  }
  return /^[\x09\x0a\x0d\x20-\x7e]+$/.test(text) ? text : '';
}

function groupFields(fields) {
  const grouped = new Map();
  for (const field of fields) {
    if (!grouped.has(field.fieldNumber)) {
      grouped.set(field.fieldNumber, []);
    }
    grouped.get(field.fieldNumber).push(field);
  }
  return grouped;
}

function firstField(grouped, fieldNumber, wireType) {
  const fields = grouped.get(fieldNumber) || [];
  return fields.find((field) => wireType === undefined || field.wireType === wireType);
}

function firstVarint(grouped, fieldNumber) {
  const field = firstField(grouped, fieldNumber, 0);
  if (!field) {
    return undefined;
  }
  return Number(field.value);
}

function firstString(grouped, fieldNumber) {
  const field = firstField(grouped, fieldNumber, 2);
  return field ? field.text : '';
}

function firstMessage(grouped, fieldNumbers) {
  for (const fieldNumber of fieldNumbers) {
    const field = firstField(grouped, fieldNumber, 2);
    if (field) {
      return field.bytes;
    }
  }
  return null;
}

function parseVpnStatus(message) {
  const top = groupFields(decodeFields(message));
  const data = firstMessage(top, [4, 3]) || message;
  const status = groupFields(decodeFields(data));
  const connectedItem = firstMessage(status, [6, 5]);
  const item = connectedItem ? groupFields(decodeFields(connectedItem)) : new Map();
  const statusCode = firstVarint(status, 1);

  return {
    code: firstVarint(top, 1) || 0,
    message: firstString(top, 2),
    statusCode,
    status: STATUS_NAMES[statusCode] || `Unknown(${statusCode})`,
    mode: firstString(status, 2),
    upSpeed: firstString(status, 3),
    downSpeed: firstString(status, 4),
    nodeId: firstVarint(item, 1),
    nodeName: firstString(item, 2),
  };
}

function parseGenericResponse(message) {
  const top = groupFields(decodeFields(message));
  return {
    code: firstVarint(top, 1) || 0,
    message: firstString(top, 2),
  };
}

function grpcFrame(payload) {
  const header = Buffer.alloc(5);
  header.writeUInt8(0, 0);
  header.writeUInt32BE(payload.length, 1);
  return Buffer.concat([header, payload]);
}

function extractGrpcMessages(buffer) {
  const messages = [];
  let offset = 0;

  while (offset + 5 <= buffer.length) {
    const compressed = buffer.readUInt8(offset);
    const length = buffer.readUInt32BE(offset + 1);
    offset += 5;
    if (compressed !== 0) {
      throw new Error('compressed grpc messages are not supported');
    }
    if (offset + length > buffer.length) {
      throw new Error('truncated grpc message');
    }
    messages.push(buffer.subarray(offset, offset + length));
    offset += length;
  }

  return messages;
}

function grpcUnary(port, methodName, payload, credentials, timeoutMs = 4000) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const body = [];
    let responseHeaders = {};
    let trailerHeaders = {};
    const client = http2.connect(`http://127.0.0.1:${port}`);

    function finish(error, value) {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      try {
        client.close();
      } catch (_) {
        // Closing is best-effort.
      }
      if (error) {
        reject(error);
      } else {
        resolve(value);
      }
    }

    const timer = setTimeout(() => {
      finish(new Error(`timeout calling ${methodName} on port ${port}`));
    }, timeoutMs);

    client.on('error', (error) => finish(error));

    const stream = client.request({
      ':method': 'POST',
      ':scheme': 'http',
      ':authority': `127.0.0.1:${port}`,
      ':path': `/server.CorpLink/${methodName}`,
      'content-type': 'application/grpc',
      te: 'trailers',
      'grpc-encoding': 'identity',
      'grpc-accept-encoding': 'identity',
      'corplink-token': credentials.token,
      'corplink-user': credentials.user,
    });

    stream.on('response', (headers) => {
      responseHeaders = headers;
    });

    stream.on('headers', (headers) => {
      if (headers['grpc-status'] !== undefined) {
        trailerHeaders = headers;
      }
    });

    stream.on('trailers', (headers) => {
      trailerHeaders = headers;
    });

    stream.on('data', (chunk) => body.push(chunk));
    stream.on('error', (error) => finish(error));
    stream.on('end', () => {
      const status = String(
        trailerHeaders['grpc-status'] ??
        responseHeaders['grpc-status'] ??
        '0',
      );
      const message = String(
        trailerHeaders['grpc-message'] ??
        responseHeaders['grpc-message'] ??
        '',
      );
      if (status !== '0') {
        finish(new Error(`grpc status ${status}${message ? `: ${message}` : ''}`));
        return;
      }

      const raw = Buffer.concat(body);
      finish(null, {
        raw,
        messages: extractGrpcMessages(raw),
      });
    });

    stream.end(grpcFrame(payload));
  });
}

async function statusOnPort(port, credentials) {
  const response = await grpcUnary(port, 'getVpnStatus', Buffer.alloc(0), credentials, 3500);
  if (response.messages.length === 0) {
    throw new Error('empty getVpnStatus response');
  }
  return parseVpnStatus(response.messages[0]);
}

async function findWorkingPort(credentials) {
  const ports = candidatePorts();
  let lastError = null;

  for (const port of ports) {
    try {
      const status = await statusOnPort(port, credentials);
      cachePort(port);
      return { port, status };
    } catch (error) {
      lastError = error;
    }
  }

  throw new Error(
    `no working Corplink RPC port found${lastError ? ` (${lastError.message})` : ''}`,
  );
}

function formatStatus(result) {
  const fields = [
    `port=${result.port}`,
    `status=${result.status.status}`,
  ];

  if (result.status.nodeName) {
    fields.push(`node="${result.status.nodeName}"`);
  }
  if (result.status.nodeId !== undefined) {
    fields.push(`node_id=${result.status.nodeId}`);
  }
  if (result.status.mode) {
    fields.push(`mode=${result.status.mode}`);
  }
  if (result.status.upSpeed) {
    fields.push(`up="${result.status.upSpeed}"`);
  }
  if (result.status.downSpeed) {
    fields.push(`down="${result.status.downSpeed}"`);
  }

  return fields.join(' ');
}

function credentials() {
  return {
    token: readToken(),
    user: currentUser(),
  };
}

async function getStatus() {
  const creds = credentials();
  return findWorkingPort(creds);
}

async function connect(config, options = {}) {
  const creds = credentials();
  let before = null;

  try {
    before = await findWorkingPort(creds);
    log(`before connect ${formatStatus(before)}`);
  } catch (error) {
    throw new Error(`cannot find RPC port before connect: ${error.message}`);
  }

  if (!options.force && before.status.statusCode === 2) {
    log('already connected; connectVpn skipped');
    return;
  }

  if (!options.force && [1, 3, 4].includes(before.status.statusCode)) {
    log(`vpn status is ${before.status.status}; connectVpn skipped`);
    return;
  }

  const payload = encodeConnectRequest(config);
  const response = await grpcUnary(before.port, 'connectVpn', payload, creds, 6000);
  const parsed = response.messages[0] ? parseGenericResponse(response.messages[0]) : { code: 0 };
  log(
    `connectVpn sent server=${config.server} mode=${config.mode}` +
    `${config.zone ? ` zone=${config.zone}` : ''}` +
    `${config.exportId !== undefined ? ` exportId=${config.exportId}` : ''}` +
    ` response_code=${parsed.code}${parsed.message ? ` response_message="${parsed.message}"` : ''}`,
  );

  await new Promise((resolve) => setTimeout(resolve, 3000));
  const after = await findWorkingPort(creds);
  log(`after connect ${formatStatus(after)}`);
}

function parseConnectArgs(argv) {
  const config = readConnectConfig();
  const options = { force: false };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--force') {
      options.force = true;
      continue;
    }
    if (arg === '--server') {
      config.server = Number.parseInt(argv[++i], 10);
      continue;
    }
    if (arg === '--mode') {
      config.mode = argv[++i];
      continue;
    }
    if (arg === '--zone') {
      config.zone = argv[++i];
      continue;
    }
    if (arg === '--export-id') {
      config.exportId = Number.parseInt(argv[++i], 10);
      continue;
    }
    if (arg === '--otp') {
      config.otp = argv[++i];
      continue;
    }
    throw new Error(`unknown argument: ${arg}`);
  }

  return { config, options };
}

async function main() {
  const command = process.argv[2] || 'status';

  if (command === 'status') {
    const result = await getStatus();
    log(formatStatus(result));
    return;
  }

  if (command === 'connect-default') {
    await connect(readConnectConfig(), {
      force: process.argv.slice(3).includes('--force'),
    });
    return;
  }

  if (command === 'connect') {
    const { config, options } = parseConnectArgs(process.argv.slice(3));
    await connect(config, options);
    return;
  }

  if (command === 'help' || command === '--help' || command === '-h') {
    console.log('usage: sealsuite-grpc.js status');
    console.log('       sealsuite-grpc.js connect-default');
    console.log('       sealsuite-grpc.js connect [--server N] [--mode Split|Full] [--zone Z] [--export-id N] [--force]');
    return;
  }

  throw new Error(`unknown command: ${command}`);
}

main().catch((error) => {
  die(error.message);
});

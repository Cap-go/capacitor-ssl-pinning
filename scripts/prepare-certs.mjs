#!/usr/bin/env node

import { cp, mkdir, readdir, rm, readFile, writeFile } from 'node:fs/promises';
import { basename, join, resolve } from 'node:path';

const rootDir = process.env.CAPACITOR_ROOT_DIR;
const webDir = process.env.CAPACITOR_WEB_DIR;
const configJson = process.env.CAPACITOR_CONFIG;

const log = (message) => console.log(`[ssl-pinning] ${message}`);
const fail = (message) => {
  throw new Error(`[ssl-pinning] ${message}`);
};

const pemToDer = (pem) => {
  const match = pem.match(/-----BEGIN CERTIFICATE-----([\s\S]*?)-----END CERTIFICATE-----/);
  if (!match) {
    return null;
  }

  const base64 = match[1].replace(/[\r\n\s]/g, '');
  if (!base64) {
    return null;
  }

  return Buffer.from(base64, 'base64');
};

if (!rootDir || !webDir || !configJson) {
  log('Capacitor hook environment not detected, skipping certificate preparation.');
  process.exit(0);
}

const config = JSON.parse(configJson);
const certs = config?.plugins?.SSLPinning?.certs;

if (!Array.isArray(certs) || certs.length === 0) {
  log('No plugins.SSLPinning.certs entries found, skipping certificate preparation.');
  process.exit(0);
}

const sourceFiles = certs.map((relativePath) => {
  if (typeof relativePath !== 'string' || !relativePath.trim()) {
    fail('All plugins.SSLPinning.certs entries must be non-empty strings.');
  }

  return {
    source: resolve(rootDir, relativePath),
    fileName: basename(relativePath),
  };
});

const targetDir = join(webDir, 'certs');
await mkdir(targetDir, { recursive: true });

for (const existingEntry of await readdir(targetDir, { withFileTypes: true })) {
  if (existingEntry.isFile()) {
    await rm(join(targetDir, existingEntry.name), { force: true });
  }
}

for (const { source, fileName } of sourceFiles) {
  const targetPath = join(targetDir, fileName);
  const buffer = await readFile(source);
  const head = buffer.subarray(0, 2048).toString('utf8');
  if (head.includes('-----BEGIN CERTIFICATE-----')) {
    const der = pemToDer(buffer.toString('utf8'));
    if (!der || der.length === 0) {
      fail(`Failed to decode PEM certificate ${fileName}.`);
    }
    await writeFile(targetPath, der);
    log(`Converted PEM ${fileName} into DER at ${targetDir}`);
    continue;
  }

  await cp(source, targetPath, { force: true });
  log(`Copied ${fileName} into ${targetDir}`);
}

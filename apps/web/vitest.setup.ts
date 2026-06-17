import '@testing-library/jest-dom/vitest';
import { webcrypto } from 'node:crypto';

// jsdom no siempre expone crypto.randomUUID; usamos el WebCrypto de Node si falta.
if (typeof globalThis.crypto?.randomUUID !== 'function') {
  Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true });
}

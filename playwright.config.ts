import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  timeout: 30_000,
  // El runtime local de Edge Functions es de un solo hilo; bajo 36 escenarios encadenados puede haber
  // flakiness de tiempo (creación de partidas/realtime). Un reintento la absorbe sin enmascarar fallos
  // reales (un fallo de verdad falla también el reintento).
  retries: 1,
  use: { baseURL: process.env.E2E_BASE_URL ?? 'http://localhost:4173' },
  projects: [
    { name: 'iphone-safari', use: { ...devices['iPhone 13'] } },
    { name: 'android-chrome', use: { ...devices['Pixel 7'] } },
  ],
});

/// <reference types="vitest/config" />
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';
import { fileURLToPath } from 'node:url';

const enginePath = fileURLToPath(new URL('../../packages/engine/src/index.ts', import.meta.url));
const sharedPath = fileURLToPath(new URL('../../packages/shared/src/index.ts', import.meta.url));

export default defineConfig({
  resolve: {
    alias: {
      // El motor compartido se consume desde su ÚNICA fuente; sin copia.
      '@multiverso/engine': enginePath,
      '@multiverso/shared': sharedPath,
    },
  },
  plugins: [
    react(),
    VitePWA({
      registerType: 'prompt', // actualización controlada: avisamos, el usuario confirma
      injectRegister: null,
      includeAssets: ['favicon.svg', 'icons/icon-192.png', 'icons/icon-512.png'],
      manifest: {
        lang: 'es',
        dir: 'ltr',
        name: 'Monopoly: El Multiverso',
        short_name: 'Multiverso',
        description: 'Gestor de partida física de Monopoly (clásico + Regreso al Futuro).',
        theme_color: '#0f172a',
        background_color: '#0f172a',
        display: 'standalone',
        orientation: 'portrait',
        start_url: '/',
        scope: '/',
        icons: [
          { src: 'icons/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any maskable' },
          { src: 'icons/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any maskable' },
        ],
      },
      workbox: {
        navigateFallback: 'index.html',
        globPatterns: ['**/*.{js,css,html,svg,png,ico,woff2}'],
        cleanupOutdatedCaches: true,
      },
      devOptions: { enabled: false },
    }),
  ],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./vitest.setup.ts'],
    css: false,
  },
});

import { test, expect } from '@playwright/test';

// Humo de Fase 0: la app carga, muestra el motor y la base sigue disponible
// tras simular pérdida de conexión (offline). Se ejecuta contra `pnpm preview`.
test('carga, muestra motor y sobrevive a offline', async ({ page, context }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: /Monopoly: El Multiverso/ })).toBeVisible();
  await expect(page.getByText(/monopoly-multiverso-engine/)).toBeVisible();

  // Simular pérdida temporal de conexión: la pantalla básica sigue disponible.
  await context.setOffline(true);
  await page.reload();
  await expect(page.getByRole('heading', { name: /Monopoly: El Multiverso/ })).toBeVisible();
  await context.setOffline(false);
});

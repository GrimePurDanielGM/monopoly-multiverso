import { test, expect, type Page } from '@playwright/test';

// Accesibilidad por teclado de los diálogos modales. Se ejecuta en Chromium y WebKit
// (proyectos android-chrome e iphone-safari) con navegación por teclado sintética,
// equivalente a usar Tab fuera de pantalla completa con teclado activo.
const PIN = '246813';

async function createGame(page: Page): Promise<string> {
  await page.goto('/crear');
  await page.getByPlaceholder('La partida del sábado').fill('A11y');
  await page.getByPlaceholder('Daniel').fill('Anfitrión');
  await page.getByRole('radiogroup', { name: 'Ficha del anfitrión' }).getByRole('radio').first().click();
  await page.getByPlaceholder('••••••').fill(PIN);
  await page.getByRole('button', { name: 'Crear y entrar' }).click();
  await page.waitForURL(/\/sala\/[A-Z0-9]{6}$/, { timeout: 30_000 });
  const m = page.url().match(/\/sala\/([A-Z0-9]{6})$/);
  if (!m) throw new Error('sin código');
  return m[1];
}

/** Abre por teclado (Safari no enfoca botones al hacer click): así el foco previo es el
 *  disparador y puede comprobarse el retorno de foco al cerrar. */
async function openByKeyboard(trigger: import('@playwright/test').Locator, page: Page) {
  await trigger.focus();
  await expect(trigger).toBeFocused();
  await page.keyboard.press('Enter');
}

/** El foco permanece dentro del diálogo al tabular varias veces (focus-trap). */
async function expectTrapped(page: Page) {
  const dialog = page.getByRole('dialog');
  await expect(dialog.locator(':focus')).toHaveCount(1); // foco inicial dentro
  for (let i = 0; i < 4; i++) {
    await page.keyboard.press('Tab');
    await expect(dialog.locator(':focus')).toHaveCount(1);
  }
  for (let i = 0; i < 4; i++) {
    await page.keyboard.press('Shift+Tab');
    await expect(dialog.locator(':focus')).toHaveCount(1);
  }
}

test('ConfirmDialog (cancelar sala): foco, trap, Escape, retorno y botón visible', async ({ page }) => {
  test.setTimeout(60_000);
  await createGame(page);

  const trigger = page.getByRole('button', { name: 'Cancelar sala' });
  await openByKeyboard(trigger, page);
  await expect(page.getByRole('dialog')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Volver' })).toBeFocused(); // foco inicial
  await expectTrapped(page);

  // Escape cierra y el foco vuelve al disparador.
  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog')).toBeHidden();
  await expect(trigger).toBeFocused();

  // Cierre mediante botón visible (sin depender de Escape).
  await trigger.click();
  await page.getByRole('button', { name: 'Volver' }).click();
  await expect(page.getByRole('dialog')).toBeHidden();
});

test('QR ampliado: foco, Escape, retorno y botón Cerrar visible', async ({ page }) => {
  test.setTimeout(60_000);
  await createGame(page);

  const trigger = page.getByRole('button', { name: 'Ampliar código QR' });
  await openByKeyboard(trigger, page);
  const dialog = page.getByRole('dialog', { name: 'Código QR ampliado' });
  await expect(dialog).toBeVisible();
  await expect(dialog.getByRole('button', { name: 'Cerrar' })).toBeFocused(); // foco inicial
  await expectTrapped(page);

  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();
  await expect(trigger).toBeFocused();

  await trigger.click();
  await dialog.getByRole('button', { name: 'Cerrar' }).click();
  await expect(dialog).toBeHidden();
});

test('Escáner QR: foco, trap, Escape, retorno y botón Cerrar visible', async ({ page }) => {
  await page.goto('/unirse');
  const trigger = page.getByRole('button', { name: 'Escanear QR' });
  await openByKeyboard(trigger, page);
  const dialog = page.getByRole('dialog', { name: 'Escanear QR' });
  await expect(dialog).toBeVisible();
  await expect(dialog.getByRole('button', { name: 'Cerrar' })).toBeFocused(); // foco inicial
  await expectTrapped(page);

  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();
  await expect(trigger).toBeFocused();

  await trigger.click();
  await dialog.getByRole('button', { name: 'Cerrar' }).click();
  await expect(dialog).toBeHidden();
});

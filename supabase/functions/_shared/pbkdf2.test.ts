// Ejecutar: deno test --allow-none supabase/functions/_shared/pbkdf2.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { hashPin, verifyPin, isWeakPin } from './pbkdf2.ts';

Deno.test('hashPin -> verifyPin: PIN correcto', async () => {
  const s = await hashPin('482915', 'pepper-test');
  assertEquals(s.iterations, 600000);
  assert(await verifyPin('482915', 'pepper-test', s));
});
Deno.test('verifyPin rechaza PIN incorrecto', async () => {
  const s = await hashPin('482915', 'pepper-test');
  assertEquals(await verifyPin('000001', 'pepper-test', s), false);
});
Deno.test('verifyPin rechaza pepper incorrecto', async () => {
  const s = await hashPin('482915', 'pepper-test');
  assertEquals(await verifyPin('482915', 'otro-pepper', s), false);
});
Deno.test('isWeakPin', () => {
  for (const w of ['000000','111111','123456','12a45','1234567','12345'])
    assert(isWeakPin(w), `débil: ${w}`);
  assertEquals(isWeakPin('482915'), false);
});

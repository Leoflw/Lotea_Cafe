// Mide el tiempo de CPU LOCAL (Node) de la parte criptográfica y de una petición
// completa con Google simulado. Es una referencia, NO la medición de Cloudflare:
// V8 en Workers es el mismo motor, pero el hardware y el límite de 10 ms (plan
// gratuito) se comprueban en producción. Ver README.md → «Límite de CPU».
//
//   node scripts/medir-cpu.mjs
import { resetAuthCache } from '../src/google-auth.js';
import { resetJwksCache } from '../src/firebase.js';
import { resetLimitador } from '../src/index.js';
import { mundoDeChat } from '../test/_helpers.js';
import { pedir } from '../test/_pedir.js';

const ms = (u) => (u.user + u.system) / 1000;
async function cpu(fn) {
  const a = process.cpuUsage();
  await fn();
  return ms(process.cpuUsage(a));
}
const mediana = (xs) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)];

const w = await mundoDeChat();
// Calentamiento del JIT: una petición cualquiera.
await pedir(w);

const frio = [];
const tibio = [];
for (let i = 0; i < 15; i++) {
  w.docs.delete(`users/uid_vendedor/deviceTokens/dev1`);
  w.ponerDispositivo('uid_vendedor', 'dev1', w.tokenValido('tokV1'));
  w.ponerConexion({ ultimoMensajeId: `c${i}`, ultimoMensajeDe: 'uid_comprador' });
  w.ponerMensaje(`c${i}`);
  const token = await w.idToken(); // se firma fuera de la medición
  resetAuthCache(); resetJwksCache(); resetLimitador(); // arranque en frío: importa la clave, firma el JWT, descarga claves
  frio.push(await cpu(() => pedir(w, { cuerpo: { tipo: 'chatMessage', connectionId: 'uid_comprador_lot1', messageId: `c${i}` }, token })));

  w.ponerConexion({ ultimoMensajeId: `t${i}`, ultimoMensajeDe: 'uid_comprador' });
  w.ponerMensaje(`t${i}`);
  tibio.push(await cpu(() => pedir(w, { cuerpo: { tipo: 'chatMessage', connectionId: 'uid_comprador_lot1', messageId: `t${i}` }, token })));
}
const fmt = (xs) => `mediana ${mediana(xs).toFixed(2)} ms · máx ${Math.max(...xs).toFixed(2)} ms`;
console.log('Petición completa con Google simulado (incluye el coste del simulador, que sobreestima):');
console.log(`  arranque en frío (importar clave + firmar JWT + verificar token): ${fmt(frio)}`);
console.log(`  petición con isolate caliente (token OAuth y claves en caché):   ${fmt(tibio)}`);
console.log('Límite del plan gratuito de Cloudflare Workers: 10 ms de CPU por petición.');

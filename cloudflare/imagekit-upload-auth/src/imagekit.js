// Parámetros de subida del lado del cliente de ImageKit.
// https://imagekit.io/docs/api-reference/upload-file/upload-file#how-to-implement-client-side-file-upload
//   signature = HMAC-SHA1( token + expire , privateKey )  en hexadecimal
// La clave privada solo existe aquí, como secreto del Worker.

function aHex(buffer) {
  return [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function firmarSubida(privateKey, token, expire) {
  const clave = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(privateKey),
    { name: 'HMAC', hash: 'SHA-1' },
    false,
    ['sign'],
  );
  const firma = await crypto.subtle.sign('HMAC', clave, new TextEncoder().encode(token + String(expire)));
  return aHex(firma);
}

# imagekit-cleanup

Worker de Cloudflare (plan gratuito) que borra de ImageKit las fotos de Lotea Café que ya nadie usa y completa
la eliminación de lotes (deja en `null` `loteFoto` del historial de ese lote). Política, arquitectura, estados,
secretos, índices y pruebas: `../../IMAGEKIT_CLEANUP.md`.
Pruebas: `npm test` (`node --test`, sin red). Despliegue (solo con autorización): `npx wrangler deploy`.

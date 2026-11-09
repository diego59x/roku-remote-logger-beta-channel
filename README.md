# roku-remote-logger-beta-channel
A BrightScript/SceneGraph library for sending logs in real time from a Roku channel (in beta) to a local server.

hi

## Seguridad

- **No envíes datos personales** (emails, tokens de usuario, etc.).
- Usa el flag `enabled` para desactivar el logger en producción.
- El servidor es solo para uso en red local de desarrollo.

## Roadmap

- [ ] Envío por lotes (batching) para evitar pérdida de eventos en ráfagas
- [ ] Persistencia en `roRegistry` cuando el servidor no esté disponible
- [ ] Soporte de HTTPS
- [ ] Publicación como paquete `ropm`
- [ ] Dashboard web en tiempo real

## Contribuir

1. Crea una rama: `git checkout -b feature/nombre`
2. Haz commit con mensajes claros
3. Abre un Pull Request y pide revisión

## Licencia

MIT

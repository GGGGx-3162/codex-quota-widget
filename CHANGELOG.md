# Changelog

## 1.3.2 — 2026-07-22

- Refresh promptly when Codex writes a new local quota record.
- Keep the 30-second periodic refresh as a reliable fallback.

## 1.3.1 — 2026-07-22

- Refresh immediately at launch, then every 30 seconds.
- Add persistent Chinese and English language switching.
- Improve Launch at Login reliability with a user LaunchAgent fallback.
- Read only the main `codex` rate-limit pool and ignore unrelated pools.
- Cache unchanged session files while invalidating the cache after new usage is written.
- Add a custom macOS app icon and packaged DMG installer.

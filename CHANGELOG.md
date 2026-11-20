# Changelog

## 0.1.0 — 2026-11-20

- Inicio de sesión con Microsoft Entra ID (OIDC Authorization Code + PKCE, single-tenant).
- Validación completa del id_token: firma con JWKS del tenant, `iss`, `aud`, `exp`/`nbf`, `nonce`, `tid` y `oid`.
- Restricción de acceso por grupos de Entra (claim `groups` o Graph `/me/checkMemberGroups`, transitivo).
- Vinculación por `oid` (`entra_id:<oid>`), vinculación de usuarios existentes por login/correo y alta automática opcional.
- Pantalla en Administración > Autenticación > Microsoft Entra ID con prueba de conexión.
- Tenant, client id y secreto sobreescribibles por variables de entorno.

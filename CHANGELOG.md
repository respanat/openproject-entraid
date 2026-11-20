# Changelog

## 0.2.0 — 2026-11-20

- Logo del botón configurable: llave, Microsoft, logo empresarial subido (PNG, JPG, GIF, WEBP o SVG validado, máx. 100 KB) o sin logo.
- Acceso con usuario y contraseña configurable: visible, plegado (enlace "Usar usuario y contraseña") u oculto, con `/login?local=1` como acceso de emergencia. Solo CSS, compatible con la CSP de OpenProject.

## 0.1.2 — 2026-11-20

- Acepta id_token firmados con la llave propia de la aplicación (`jwks_uri?appid=<client_id>`). Necesario cuando la aplicación empresarial tiene SSO SAML o claims mapping configurado.

## 0.1.1 — 2026-11-20

- Corrige error 500 en /entra_id/login y /entra_id/callback: el controlador sobreescribía el método `config` de ActionController.

## 0.1.0 — 2026-11-20

- Inicio de sesión con Microsoft Entra ID (OIDC Authorization Code + PKCE, single-tenant).
- Validación completa del id_token: firma con JWKS del tenant, `iss`, `aud`, `exp`/`nbf`, `nonce`, `tid` y `oid`.
- Restricción de acceso por grupos de Entra (claim `groups` o Graph `/me/checkMemberGroups`, transitivo).
- Vinculación por `oid` (`entra_id:<oid>`), vinculación de usuarios existentes por login/correo y alta automática opcional.
- Pantalla en Administración > Autenticación > Microsoft Entra ID con prueba de conexión.
- Tenant, client id y secreto sobreescribibles por variables de entorno.

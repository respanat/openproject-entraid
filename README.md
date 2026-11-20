# openproject-entra_id

Plugin para **OpenProject Community** que agrega el botón **"Iniciar sesión con Microsoft"** usando
**Microsoft Entra ID** (OpenID Connect), con restricción opcional por grupos de Entra.

## Por qué un plugin propio

En OpenProject, el SSO por OpenID Connect/SAML es una función Enterprise: todo proveedor OmniAuth
registrado con `OpenProject::Plugins::AuthPlugin` pasa por `filtered_strategy?`, que exige el token
Enterprise `sso_auth_providers`. Este plugin **no toca ese mecanismo**: implementa su propio flujo
OIDC (controlador propio + validación del token) y entrega el usuario al flujo normal de inicio de
sesión del core (`successful_authentication`), así que se respetan 2FA, consentimiento, límites de
usuarios y redirecciones posteriores al login.

## Qué hace

| Función | Detalle |
|---|---|
| Login con Entra | Authorization Code + PKCE (S256), `state` y `nonce`, solo single-tenant |
| Validación del token | Firma RS256 con el JWKS del tenant, `iss`, `aud`, `exp`/`nbf`, `nonce`, `tid`, `oid` |
| Restringir por grupo | Lista de IDs de objeto de grupos. Usa el claim `groups` si viene; si no, consulta Graph `/me/checkMemberGroups` (transitivo, maneja el *overage* de grupos). Si Graph falla, niega el acceso |
| Usuarios | Vincula por `oid` (`entra_id:<oid>`). Opcional: vincular usuarios existentes por login/correo (una sola vez) y crear usuarios nuevos automáticamente |
| Perfil | Nombre, apellido y correo desde Graph `/me` (con respaldo en los claims) |
| Admin | *Administración → Autenticación → Microsoft Entra ID*, con botón para probar la conexión |

Nunca concede ni retira el rol de administrador.

## Requisitos

- OpenProject Community instalado por paquete (DEB/RPM) 15.x o superior. Desarrollado contra el
  código de la rama `dev` (18.1). Soporta el esquema nuevo de vínculos (`user_auth_provider_links`,
  16.1+) y la columna antigua `users.identity_url`.
- El servidor de OpenProject debe poder salir por HTTPS a `login.microsoftonline.com` y
  `graph.microsoft.com`.
- El nombre de host y el protocolo de *Administración → Sistema* deben ser los públicos (`https`).

## 1. Registrar la aplicación en Entra ID

1. **Entra admin center → Identidad → Aplicaciones → Registros de aplicaciones → Nuevo registro.**
   - Tipos de cuenta: *Solo las cuentas de este directorio organizativo*.
   - URI de redirección: plataforma **Web** →
     `https://TU-OPENPROJECT/entra_id/callback`
     (la URI exacta aparece en la pantalla de administración del plugin).
2. Copia el **ID de aplicación (cliente)** y el **ID de directorio (tenant)**.
3. **Certificados y secretos → Nuevo secreto de cliente.** Copia el **Valor** (no el ID del secreto).
   Anota la fecha de caducidad.
4. **Permisos de API:** basta `Microsoft Graph → User.Read` (delegado), que viene por defecto.
   Concede consentimiento de administrador para evitar la pantalla de consentimiento a cada usuario.
5. *(Opcional, recomendado si restringes por grupo)* **Configuración de token → Agregar
   notificación de grupos → Grupos de seguridad**, con *ID de grupo*. Si no lo haces, el plugin
   consulta Graph en cada login (igual funciona).
6. *(Opcional, capa extra)* En **Aplicaciones empresariales → tu app → Propiedades** activa
   *¿Se requiere asignación?* y asigna los grupos. Así Entra bloquea antes de llegar a OpenProject.

## 2. Instalar en OpenProject (paquete)

```bash
sudo tee /etc/openproject/Gemfile.custom > /dev/null <<'EOF'
group :opf_plugins do
  gem "openproject-entra_id", git: "https://github.com/respanat/openproject-entraid.git", branch: "main"
end
EOF

sudo openproject config:set CUSTOM_PLUGIN_GEMFILE="/etc/openproject/Gemfile.custom"

# Recomendado: el secreto fuera de la base de datos
sudo openproject config:set ENTRA_ID_CLIENT_SECRET="valor-del-secreto"
# Opcionales (si no, se configuran en la pantalla de admin)
sudo openproject config:set ENTRA_ID_TENANT_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
sudo openproject config:set ENTRA_ID_CLIENT_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

sudo openproject configure   # vuelve a empaquetar con el plugin y reinicia
```

Haz un respaldo antes (`sudo openproject run backup`) y prueba primero en un servidor de pruebas.

## 3. Configurar

*Administración → Autenticación → Microsoft Entra ID*:

1. Pega tenant, client id y secreto (si no los pusiste por variable de entorno).
2. **Probar conexión con el tenant**.
3. Grupos autorizados: IDs de objeto, uno por línea (vacío = cualquier usuario del tenant).
4. Elige si se crean usuarios automáticamente y si se vinculan los existentes por login/correo.
5. Marca **Activar** y guarda. El botón aparece en la página de inicio de sesión.

Conserva siempre un administrador local con contraseña por si Entra no está disponible.

## Desinstalar

Quita la línea del `Gemfile.custom` (o la opción `CUSTOM_PLUGIN_GEMFILE`) y ejecuta
`sudo openproject configure`. El plugin no crea tablas; los vínculos `entra_id:<oid>` quedan en
`user_auth_provider_links` y no afectan el login por contraseña.

## Pruebas

La lógica OIDC (validación del token, PKCE, grupos, perfil) se prueba de forma aislada:

```bash
ruby -I /ruta/a/ruby-jwt/lib test/oidc_test.rb
```

## Licencia

GPL-3.0, igual que OpenProject.

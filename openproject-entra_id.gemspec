# frozen_string_literal: true


Gem::Specification.new do |s|
  s.name        = "openproject-entra_id"
  s.version     = "0.2.2"
  s.authors     = ["Ramiro España"]
  s.homepage    = "https://github.com/respanat/openproject-entraid"
  s.summary     = "Inicio de sesión con Microsoft Entra ID para OpenProject Community"
  s.description = "Plugin para OpenProject Community que permite iniciar sesión con Microsoft Entra ID " \
                  "(OpenID Connect con PKCE), vincular o crear usuarios y restringir el acceso por grupos de Entra."
  s.license     = "GPL-3.0-only"

  s.required_ruby_version = ">= 3.2"

  s.files = Dir["{app,config,lib}/**/*"] + %w[README.md CHANGELOG.md LICENSE]

  # jwt ya viene incluido en el bundle de OpenProject (lo usa el core).
  s.add_dependency "jwt", ">= 2.7", "< 4"

  s.metadata["rubygems_mfa_required"] = "true"
end

# frozen_string_literal: true

module OpenProject
  module EntraId
    VERSION = "0.1.2"

    # Slug con el que se guarda el vínculo usuario <-> Entra (identity_url = "entra_id:<oid>").
    PROVIDER_SLUG = "entra_id"

    class Error < StandardError; end

    # Fallo del flujo de login que se registra en el log y se muestra genérico al usuario.
    class LoginError < Error; end

    def self.configuration
      Configuration.current
    end
  end
end

require "open_project/entra_id/configuration"
require "open_project/entra_id/http"
require "open_project/entra_id/oidc_client"
require "open_project/entra_id/graph_client"
require "open_project/entra_id/engine" if defined?(Rails::Engine)

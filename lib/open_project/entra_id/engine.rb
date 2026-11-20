# frozen_string_literal: true

require "open_project/plugins"

module OpenProject
  module EntraId
    class Engine < ::Rails::Engine
      engine_name :openproject_entra_id

      include OpenProject::Plugins::ActsAsOpEngine

      register "openproject-entra_id",
               author_url: "https://github.com/respanat/openproject-entraid",
               settings: { default: OpenProject::EntraId::Configuration::DEFAULTS.dup } do
        menu :admin_menu,
             :plugin_entra_id,
             { controller: "/entra_id/settings", action: :show },
             parent: :authentication,
             caption: ->(*) { I18n.t("entra_id.menu_title") }
      end

      config.to_prepare do
        OpenProject::EntraId::Hooks
      end

      ##
      # URL de retorno que debe registrarse en Entra como "Redirect URI" (tipo Web).
      # Se construye con el host y protocolo configurados en OpenProject
      # (Administración > Sistema), no con la cabecera Host de la petición.
      def self.callback_url(request = nil)
        base =
          if defined?(OpenProject::StaticRouting::StaticUrlHelpers)
            OpenProject::StaticRouting::StaticUrlHelpers.new.root_url
          elsif request
            "#{request.base_url}#{OpenProject::Configuration.rails_relative_url_root}/"
          end
        URI.join(base.end_with?("/") ? base : "#{base}/", "entra_id/callback").to_s
      end
    end
  end
end

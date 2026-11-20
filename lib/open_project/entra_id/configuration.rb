# frozen_string_literal: true

module OpenProject
  module EntraId
    ##
    # Configuración del plugin.
    #
    # Los valores se guardan en Setting.plugin_openproject_entra_id (pantalla de
    # administración). Tenant, client id y secreto pueden sobreescribirse con
    # variables de entorno, recomendado para el secreto en instalaciones por paquete:
    #
    #   sudo openproject config:set ENTRA_ID_CLIENT_SECRET="..."
    #
    class Configuration
      SETTING_NAME = "plugin_openproject_entra_id"

      ENV_KEYS = {
        "tenant_id" => "ENTRA_ID_TENANT_ID",
        "client_id" => "ENTRA_ID_CLIENT_ID",
        "client_secret" => "ENTRA_ID_CLIENT_SECRET"
      }.freeze

      DEFAULTS = {
        "enabled" => false,
        "tenant_id" => "",
        "client_id" => "",
        "client_secret" => "",
        "button_label" => "Iniciar sesión con Microsoft",
        "allowed_group_ids" => "",
        "auto_create_users" => true,
        "link_existing_users" => true,
        "login_attribute" => "upn", # upn | mail
        "update_user_on_login" => true,
        "button_logo" => "key", # key | microsoft | custom | none
        "custom_logo" => "", # data URI (image/png, image/jpeg, image/gif, image/webp, image/svg+xml)
        "local_login_mode" => "visible" # visible | collapsed | hidden
      }.freeze

      BUTTON_LOGOS = %w[key microsoft custom none].freeze
      LOCAL_LOGIN_MODES = %w[visible collapsed hidden].freeze

      GUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

      attr_reader :values

      def self.current
        raw = defined?(::Setting) ? (::Setting[SETTING_NAME] rescue nil) : nil # rubocop:disable Style/RescueModifier
        new(raw || {}, ENV)
      end

      def initialize(settings_hash, env = {})
        @values = DEFAULTS.merge(stringify(settings_hash))
        @env = env
      end

      def enabled? = truthy?(values["enabled"])
      def auto_create_users? = truthy?(values["auto_create_users"])
      def link_existing_users? = truthy?(values["link_existing_users"])
      def update_user_on_login? = truthy?(values["update_user_on_login"])

      def tenant_id = env_or("tenant_id").to_s.strip.downcase
      def client_id = env_or("client_id").to_s.strip
      def client_secret = env_or("client_secret").to_s

      def from_env?(key)
        ENV_KEYS.key?(key) && @env[ENV_KEYS[key]].to_s.strip != ""
      end

      def button_label
        label = values["button_label"].to_s.strip
        label.empty? ? DEFAULTS["button_label"] : label
      end

      def button_logo
        logo = values["button_logo"].to_s
        logo = "key" unless BUTTON_LOGOS.include?(logo)
        logo == "custom" && custom_logo.empty? ? "key" : logo
      end

      def custom_logo
        values["custom_logo"].to_s.start_with?("data:image/") ? values["custom_logo"].to_s : ""
      end

      def local_login_mode
        mode = values["local_login_mode"].to_s
        LOCAL_LOGIN_MODES.include?(mode) ? mode : "visible"
      end

      def login_attribute
        values["login_attribute"].to_s == "mail" ? "mail" : "upn"
      end

      # IDs de objeto de grupos de Entra separados por coma, espacio o salto de línea.
      def allowed_group_ids
        values["allowed_group_ids"].to_s.split(/[\s,;]+/).map { |id| id.strip.downcase }.reject(&:empty?).uniq
      end

      def restrict_by_group? = allowed_group_ids.any?

      def invalid_group_ids
        allowed_group_ids.grep_v(GUID)
      end

      # Listo para mostrar el botón y procesar logins.
      def usable?
        enabled? && configuration_errors.empty?
      end

      def configuration_errors
        errors = []
        errors << :tenant_id unless tenant_id.match?(GUID)
        errors << :client_id unless client_id.match?(GUID)
        errors << :client_secret if client_secret.empty?
        errors << :allowed_group_ids if invalid_group_ids.any?
        errors
      end

      def authority = "https://login.microsoftonline.com/#{tenant_id}/v2.0"
      def discovery_url = "#{authority}/.well-known/openid-configuration"
      def expected_issuer = "https://login.microsoftonline.com/#{tenant_id}/v2.0"

      private

      def env_or(key)
        from_env?(key) ? @env[ENV_KEYS[key]] : values[key]
      end

      def truthy?(value)
        [true, "true", "1", 1, "on", "yes"].include?(value)
      end

      def stringify(hash)
        (hash.respond_to?(:to_h) ? hash.to_h : {}).each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }
      end
    end
  end
end

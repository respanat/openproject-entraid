# frozen_string_literal: true

module EntraId
  ##
  # Administración > Autenticación > Microsoft Entra ID
  class SettingsController < ::ApplicationController
    layout "admin"

    before_action :require_admin

    menu_item :plugin_entra_id if respond_to?(:menu_item)

    BOOLEAN_KEYS = %w[enabled auto_create_users link_existing_users update_user_on_login].freeze
    TEXT_KEYS = %w[tenant_id client_id button_label allowed_group_ids login_attribute].freeze

    def show
      @entra_config = OpenProject::EntraId.configuration
      @callback_url = OpenProject::EntraId::Engine.callback_url(request)
      @linked_users = EntraId::Compat.linked_users_count
    end

    def update
      current = OpenProject::EntraId.configuration.values
      incoming = params.fetch(:entra_id, {}).permit(*TEXT_KEYS, *BOOLEAN_KEYS, :client_secret, :clear_secret)

      updated = current.merge(TEXT_KEYS.to_h { |k| [k, incoming[k].to_s.strip] })
      BOOLEAN_KEYS.each { |k| updated[k] = incoming[k] == "1" }

      # El secreto nunca se devuelve al formulario: vacío = conservar el actual.
      if incoming[:clear_secret] == "1"
        updated["client_secret"] = ""
      elsif incoming[:client_secret].present?
        updated["client_secret"] = incoming[:client_secret].strip
      end

      Setting[OpenProject::EntraId::Configuration::SETTING_NAME] = updated
      OpenProject::EntraId::OidcClient.clear_cache!

      errors = OpenProject::EntraId::Configuration.new(updated, ENV).configuration_errors
      if updated["enabled"] && errors.any?
        flash[:warning] = I18n.t("entra_id.settings.saved_with_errors",
                                 fields: errors.map { |e| I18n.t("entra_id.settings.fields.#{e}") }.join(", "))
      else
        flash[:notice] = I18n.t(:notice_successful_update)
      end

      redirect_to entra_id_settings_path
    end

    # Comprueba que el tenant responde (documento de descubrimiento y JWKS).
    def test
      entra_config = OpenProject::EntraId.configuration
      client = OpenProject::EntraId::OidcClient.new(entra_config)
      metadata = client.metadata(force: true)
      issuer_ok = metadata["issuer"].to_s.casecmp?(entra_config.expected_issuer)

      if issuer_ok
        flash[:notice] = I18n.t("entra_id.settings.test_ok", issuer: metadata["issuer"])
      else
        flash[:error] = I18n.t("entra_id.settings.test_issuer_mismatch", issuer: metadata["issuer"])
      end
      redirect_to entra_id_settings_path
    rescue OpenProject::EntraId::Error, KeyError => e
      flash[:error] = I18n.t("entra_id.settings.test_failed", message: e.message)
      redirect_to entra_id_settings_path
    end
  end
end

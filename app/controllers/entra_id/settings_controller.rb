# frozen_string_literal: true

module EntraId
  ##
  # Administración > Autenticación > Microsoft Entra ID
  class SettingsController < ::ApplicationController
    layout "admin"

    before_action :require_admin

    menu_item :plugin_entra_id if respond_to?(:menu_item)

    BOOLEAN_KEYS = %w[enabled auto_create_users link_existing_users update_user_on_login].freeze
    TEXT_KEYS = %w[tenant_id client_id button_label allowed_group_ids login_attribute
                   button_logo local_login_mode logo_layout].freeze

    def show
      @entra_config = OpenProject::EntraId.configuration
      @callback_url = OpenProject::EntraId::Engine.callback_url(request)
      @linked_users = EntraId::Compat.linked_users_count
    end

    def update
      current = OpenProject::EntraId.configuration.values
      incoming = params.fetch(:entra_id, {}).permit(*TEXT_KEYS, *BOOLEAN_KEYS, :client_secret, :clear_secret,
                                                         :custom_logo_file, :remove_custom_logo)

      updated = current.merge(TEXT_KEYS.to_h { |k| [k, incoming[k].to_s.strip] })
      BOOLEAN_KEYS.each { |k| updated[k] = incoming[k] == "1" }

      # El secreto nunca se devuelve al formulario: vacío = conservar el actual.
      if incoming[:clear_secret] == "1"
        updated["client_secret"] = ""
      elsif incoming[:client_secret].present?
        updated["client_secret"] = incoming[:client_secret].strip
      end

      logo_error = apply_logo(updated, incoming)

      Setting[OpenProject::EntraId::Configuration::SETTING_NAME] = updated
      OpenProject::EntraId::OidcClient.clear_cache!

      errors = OpenProject::EntraId::Configuration.new(updated, ENV).configuration_errors
      if logo_error
        flash[:error] = I18n.t("entra_id.settings.#{logo_error}", max: OpenProject::EntraId::LogoUpload::MAX_BYTES / 1024)
      elsif updated["enabled"] && errors.any?
        flash[:warning] = I18n.t("entra_id.settings.saved_with_errors",
                                 fields: errors.map { |e| I18n.t("entra_id.settings.fields.#{e}") }.join(", "))
      else
        flash[:notice] = I18n.t(:notice_successful_update)
      end

      redirect_to entra_id_settings_path
    end

    private

    # Devuelve la clave i18n del error o nil.
    def apply_logo(updated, incoming)
      if incoming[:remove_custom_logo] == "1"
        updated["custom_logo"] = ""
        updated["button_logo"] = "key" if updated["button_logo"] == "custom"
        return nil
      end

      file = incoming[:custom_logo_file]
      return nil unless file.respond_to?(:read)

      updated["custom_logo"] = OpenProject::EntraId::LogoUpload.to_data_uri(file.read(OpenProject::EntraId::LogoUpload::MAX_BYTES + 1))
      updated["button_logo"] = "custom"
      nil
    rescue OpenProject::EntraId::LogoUpload::Invalid => e
      updated["custom_logo"] = OpenProject::EntraId.configuration.values["custom_logo"].to_s
      e.message
    end

    public

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

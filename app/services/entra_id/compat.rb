# frozen_string_literal: true

module EntraId
  ##
  # Diferencias entre versiones de OpenProject:
  #
  # * 16.1+ guarda la identidad externa en user_auth_provider_links, ligada a
  #   un AuthProvider (aquí un PluginAuthProvider con slug "entra_id").
  # * Versiones anteriores usan la columna users.identity_url.
  module Compat
    DISPLAY_NAME = "Microsoft Entra ID"

    module_function

    def provider_links?
      defined?(::UserAuthProviderLink) && defined?(::PluginAuthProvider) &&
        ::UserAuthProviderLink.table_exists?
    end

    def ensure_auth_provider!
      return unless provider_links?

      ::PluginAuthProvider.find_or_create_by!(slug: OpenProject::EntraId::PROVIDER_SLUG) do |provider|
        provider.display_name = DISPLAY_NAME
        provider.creator = ::User.system
        provider.available = true if provider.respond_to?(:available=)
      end
    end

    def find_user_by_identity_url(identity_url)
      if provider_links?
        ::UserAuthProviderLink
          .left_joins(:principal)
          .where(principal: { type: "User" })
          .with_identity_url(identity_url)
          .first
          &.principal
      else
        ::User.not_builtin.find_by(identity_url:)
      end
    end

    # oid de Entra con el que ya está vinculado el usuario (o nil).
    def external_id_for(user)
      if provider_links?
        provider = ::AuthProvider.find_by(slug: OpenProject::EntraId::PROVIDER_SLUG)
        return nil unless provider

        user.user_auth_provider_links.find_by(auth_provider: provider)&.external_id
      else
        slug, external_id = user.identity_url.to_s.split(":", 2)
        external_id if slug == OpenProject::EntraId::PROVIDER_SLUG
      end
    end

    def linked_users_count
      if provider_links?
        provider = ::AuthProvider.find_by(slug: OpenProject::EntraId::PROVIDER_SLUG)
        provider ? provider.user_auth_provider_links.count : 0
      else
        ::User.where("identity_url LIKE ?", "#{OpenProject::EntraId::PROVIDER_SLUG}:%").count
      end
    end
  end
end

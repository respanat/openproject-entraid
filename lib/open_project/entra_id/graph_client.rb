# frozen_string_literal: true

require "open_project/entra_id/http"

module OpenProject
  module EntraId
    ##
    # Llamadas a Microsoft Graph con el token delegado del usuario (permiso User.Read).
    class GraphClient
      BASE = "https://graph.microsoft.com/v1.0"
      PROFILE_FIELDS = %w[id displayName givenName surname mail userPrincipalName].freeze
      # checkMemberGroups acepta hasta 20 IDs por petición.
      CHECK_BATCH = 20

      def initialize(access_token, http: Http)
        @access_token = access_token
        @http = http
      end

      def me
        @http.get_json("#{BASE}/me?$select=#{PROFILE_FIELDS.join(',')}", headers: auth)
      end

      ##
      # Devuelve los IDs (en minúscula) de group_ids de los que el usuario es
      # miembro, de forma transitiva. Funciona aunque haya "overage" de grupos.
      def member_of(group_ids)
        group_ids.each_slice(CHECK_BATCH).flat_map do |batch|
          result = @http.post_json("#{BASE}/me/checkMemberGroups", { groupIds: batch }, headers: auth)
          Array(result["value"]).map { |id| id.to_s.downcase }
        end
      end

      private

      def auth
        { "Authorization" => "Bearer #{@access_token}" }
      end
    end
  end
end

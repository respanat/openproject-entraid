# frozen_string_literal: true

require "base64"
require "digest"
require "monitor"
require "securerandom"
require "jwt"
require "open_project/entra_id/http"

module OpenProject
  module EntraId
    ##
    # Flujo Authorization Code + PKCE contra Microsoft identity platform v2.0,
    # implementado sin OmniAuth para no depender del filtro Enterprise de
    # OpenProject::Plugins::AuthPlugin.
    class OidcClient
      SCOPES = %w[openid profile email https://graph.microsoft.com/User.Read].freeze
      METADATA_TTL = 3600
      CLOCK_SKEW = 120

      @cache = {}
      @cache_lock = Monitor.new # reentrante: JWKS consulta metadata dentro del bloque

      class << self
        def cached(key, ttl: METADATA_TTL, force: false)
          @cache_lock.synchronize do
            entry = @cache[key]
            return entry[:value] if !force && entry && entry[:expires_at] > Time.now

            value = yield
            @cache[key] = { value:, expires_at: Time.now + ttl }
            value
          end
        end

        def clear_cache!
          @cache_lock.synchronize { @cache.clear }
        end

        def random_token(bytes = 32)
          Base64.urlsafe_encode64(SecureRandom.random_bytes(bytes), padding: false)
        end

        def code_challenge(verifier)
          Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
        end
      end

      attr_reader :config

      def initialize(config, http: Http)
        @config = config
        @http = http
      end

      def metadata(force: false)
        self.class.cached("metadata:#{config.tenant_id}", force:) do
          @http.get_json(config.discovery_url)
        end
      end

      def authorization_url(redirect_uri:, state:, nonce:, code_verifier:, login_hint: nil)
        params = {
          client_id: config.client_id,
          response_type: "code",
          response_mode: "query",
          redirect_uri:,
          scope: SCOPES.join(" "),
          state:,
          nonce:,
          code_challenge: self.class.code_challenge(code_verifier),
          code_challenge_method: "S256",
          prompt: "select_account"
        }
        params[:login_hint] = login_hint if login_hint
        "#{metadata.fetch('authorization_endpoint')}?#{URI.encode_www_form(params)}"
      end

      def exchange_code(code:, redirect_uri:, code_verifier:)
        @http.post_form(metadata.fetch("token_endpoint"), {
                          client_id: config.client_id,
                          client_secret: config.client_secret,
                          grant_type: "authorization_code",
                          code:,
                          redirect_uri:,
                          code_verifier:,
                          scope: SCOPES.join(" ")
                        })
      rescue Http::Error => e
        detail = e.body.is_a?(Hash) ? e.body["error_description"].to_s.lines.first : nil
        raise LoginError, ["Entra rechazó el intercambio del código", detail].compact.join(": ")
      end

      ##
      # Valida firma (JWKS del tenant), iss, aud, exp, nbf, nonce y tid.
      # Devuelve los claims del id_token.
      def validate_id_token(id_token, nonce:)
        claims, = JWT.decode(
          id_token, nil, true,
          algorithms: ["RS256"],
          jwks: jwks_loader,
          iss: config.expected_issuer, verify_iss: true,
          aud: config.client_id, verify_aud: true,
          verify_expiration: true, verify_not_before: true,
          leeway: CLOCK_SKEW
        )

        raise LoginError, "nonce inválido" unless secure_compare(claims["nonce"].to_s, nonce.to_s)
        raise LoginError, "El token pertenece a otro tenant" unless claims["tid"].to_s.downcase == config.tenant_id
        raise LoginError, "El token no trae el identificador de objeto (oid)" if claims["oid"].to_s.empty?

        claims
      rescue JWT::DecodeError => e
        raise LoginError, "id_token inválido: #{e.message}"
      end

      private

      def jwks_loader
        lambda do |options|
          force = options[:kid_not_found] || options[:invalidate]
          keys = self.class.cached("jwks:#{config.tenant_id}:#{config.client_id}", force:) do
            merged_jwks
          end
          JWT::JWK::Set.new(keys)
        end
      end

      ##
      # Claves del tenant + claves propias de la aplicación.
      # Si la app tiene un certificado de firma propio (p. ej. SSO SAML configurado
      # en la aplicación empresarial o claims mapping), Entra firma los id_token
      # con esa llave y solo la publica en jwks_uri?appid=<client_id>.
      def merged_jwks
        uri = metadata.fetch("jwks_uri")
        separator = uri.include?("?") ? "&" : "?"
        app_uri = "#{uri}#{separator}appid=#{URI.encode_www_form_component(config.client_id)}"

        keys = Array(@http.get_json(uri)["keys"])
        begin
          keys += Array(@http.get_json(app_uri)["keys"])
        rescue Http::Error
          # Sin claves propias de la app: basta con las del tenant.
        end
        { "keys" => keys.uniq { |k| k["kid"] || k[:kid] || k } }
      end

      def secure_compare(left, right)
        return false if left.empty? || left.bytesize != right.bytesize

        left.bytes.zip(right.bytes).reduce(0) { |acc, (a, b)| acc | (a ^ b) }.zero?
      end
    end
  end
end

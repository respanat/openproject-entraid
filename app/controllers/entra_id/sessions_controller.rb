# frozen_string_literal: true

module EntraId
  ##
  # GET /entra_id/login    -> redirige a Entra (Authorization Code + PKCE)
  # GET /entra_id/callback -> valida la respuesta, aplica la restricción por
  #                           grupo, vincula/crea el usuario e inicia sesión
  #                           usando las etapas de autenticación del core (2FA, etc.).
  class SessionsController < ::ApplicationController
    include ::Accounts::Registration
    include ::Accounts::UserLogin

    PENDING_KEY = :entra_id_pending_auth
    MAX_FLOW_AGE = 600 # segundos

    skip_before_action :check_if_login_required
    skip_before_action :check_session_lifetime, raise: false
    no_authorization_required!(:login, :callback) if respond_to?(:no_authorization_required!)

    before_action :require_usable_configuration

    layout "no_menu"

    def login
      verifier = client_class.random_token(48)
      session[PENDING_KEY] = {
        "state" => client_class.random_token,
        "nonce" => client_class.random_token,
        "verifier" => verifier,
        "created_at" => Time.now.to_i
      }
      session[:back_url] = params[:back_url] if safe_back_url?(params[:back_url])

      pending = session[PENDING_KEY]
      redirect_to client.authorization_url(redirect_uri: callback_url,
                                           state: pending["state"],
                                           nonce: pending["nonce"],
                                           code_verifier: verifier,
                                           login_hint: params[:login_hint].presence),
                  allow_other_host: true
    rescue OpenProject::EntraId::Error => e
      fail_login(:connection_error, e.message)
    end

    def callback
      pending = session.delete(PENDING_KEY)
      return fail_login(:entra_error, entra_error_detail) if params[:error].present?
      return fail_login(:invalid_state) unless valid_pending?(pending)

      tokens = client.exchange_code(code: params.require(:code),
                                    redirect_uri: callback_url,
                                    code_verifier: pending["verifier"])
      claims = client.validate_id_token(tokens.fetch("id_token"), nonce: pending["nonce"])
      graph = OpenProject::EntraId::GraphClient.new(tokens.fetch("access_token"))

      gate = EntraId::GroupGate.new(config, claims, graph).call
      return fail_login(gate.reason || :not_in_allowed_group, claims["preferred_username"]) unless gate.allowed?

      profile = EntraId::Profile.new(claims, fetch_graph_profile(graph), login_attribute: config.login_attribute)
      result = EntraId::UserProvisioner.new(profile, config).call
      return fail_login(result.error, profile.to_s) unless result.success?

      logger.info("[entra_id] Inicio de sesión de #{profile}")
      login_user_if_active(result.user, just_registered: result.just_created)
    rescue ActionController::ParameterMissing, KeyError
      fail_login(:invalid_response)
    rescue OpenProject::EntraId::Error => e
      fail_login(:login_failed, e.message)
    end

    private

    def config
      @config ||= OpenProject::EntraId.configuration
    end

    def client_class = OpenProject::EntraId::OidcClient

    def client
      @client ||= client_class.new(config)
    end

    def callback_url
      OpenProject::EntraId::Engine.callback_url(request)
    end

    def require_usable_configuration
      render_404 unless config.usable?
    end

    def valid_pending?(pending)
      return false unless pending.is_a?(Hash) && params[:state].present?
      return false if Time.now.to_i - pending["created_at"].to_i > MAX_FLOW_AGE

      ActiveSupport::SecurityUtils.secure_compare(pending["state"].to_s, params[:state].to_s)
    end

    def fetch_graph_profile(graph)
      graph.me
    rescue OpenProject::EntraId::Http::Error => e
      logger.warn("[entra_id] No se pudo leer /me en Graph, se usan los claims del token: #{e.message}")
      {}
    end

    def entra_error_detail
      [params[:error], params[:error_description].to_s.lines.first].compact_blank.join(": ")
    end

    # Solo rutas relativas del mismo sitio.
    def safe_back_url?(url)
      url.is_a?(String) && url.start_with?("/") && !url.start_with?("//") && !url.include?("\\")
    end

    def fail_login(code, detail = nil)
      logger.warn("[entra_id] Login fallido (#{code})#{" - #{detail}" if detail}")
      flash[:error] = I18n.t("entra_id.errors.#{code}", default: I18n.t("entra_id.errors.login_failed"))
      redirect_to signin_path
    end
  end
end

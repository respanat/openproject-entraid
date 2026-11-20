# frozen_string_literal: true

module EntraId
  ##
  # Busca, vincula o crea el usuario de OpenProject correspondiente a un
  # perfil de Entra, replicando la lógica de Authentication::OmniauthService
  # del core:
  #
  #   1. Usuario ya vinculado (identity_url "entra_id:<oid>")
  #   2. Usuario existente con el mismo login o correo (si está habilitado)
  #   3. Usuario nuevo (si está habilitado el alta automática)
  #
  # Nunca concede ni retira permisos de administrador.
  class UserProvisioner
    Result = Struct.new(:user, :error, :just_created, keyword_init: true) do
      def success? = error.nil?
    end

    def initialize(profile, config)
      @profile = profile
      @config = config
    end

    def call
      EntraId::Compat.ensure_auth_provider!

      user = find_linked_user
      linked = user.present?
      user ||= find_existing_user if @config.link_existing_users?

      if user.nil?
        return failure(:user_not_found) unless @config.auto_create_users?

        user = User.new
      end

      return failure(:account_locked) if user.locked?

      new_record = user.new_record?
      call = assign_attributes(user, linked:)
      return failure(:invalid_user, call.message) unless call.success?

      if activatable?(user)
        activation = ::Users::RegisterUserService.new(user).call
        return failure(:activation_failed, activation.message) unless activation.success?

        user = activation.result
      end

      Result.new(user:, just_created: new_record)
    end

    private

    def find_linked_user
      EntraId::Compat.find_user_by_identity_url(@profile.identity_url)
    end

    def find_existing_user
      keys = [@profile.login, @profile.mail.to_s.downcase, @profile.upn.to_s.downcase].reject(&:empty?).uniq
      user = User.not_builtin
                 .where("LOWER(login) IN (:keys) OR LOWER(mail) IN (:keys)", keys:)
                 .order(:id)
                 .first
      return if user.nil?

      other = EntraId::Compat.external_id_for(user)
      if other.present? && other != @profile.external_id
        log("#{user.login} ya está vinculado a otro oid de Entra (#{other}); no se revincula a #{@profile.external_id}")
        return nil
      end

      log("Vinculando usuario existente #{user.login} con #{@profile}")
      user
    end

    def assign_attributes(user, linked:)
      attrs = { identity_url: @profile.identity_url }

      if user.new_record? || user.invited?
        attrs.merge!(login: @profile.login, mail: @profile.mail,
                     firstname: @profile.firstname, lastname: @profile.lastname)
        user.register unless user.invited?

        ::Users::SetAttributesService
          .new(user: User.system, model: user, contract_class: ::Users::UpdateContract)
          .call(attrs)
      else
        if @config.update_user_on_login?
          attrs.merge!(mail: @profile.mail, firstname: @profile.firstname, lastname: @profile.lastname)
        end
        attrs.delete(:identity_url) if linked

        ::Users::UpdateService.new(user: User.system, model: user).call(attrs)
      end
    end

    # Igual que en OmniauthService: recién creado, invitado o pendiente de activación.
    def activatable?(user)
      user.new_record? || user.invited? || user.registered?
    end

    def failure(code, detail = nil)
      log("Login rechazado (#{code}) para #{@profile}#{": #{detail}" if detail}")
      Result.new(error: code)
    end

    def log(message)
      Rails.logger.info("[entra_id] #{message}")
    end
  end
end

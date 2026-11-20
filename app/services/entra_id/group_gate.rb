# frozen_string_literal: true

module EntraId
  ##
  # Decide si el usuario puede entrar según los grupos de Entra configurados.
  #
  # 1. Si el claim "groups" del id_token ya contiene alguno de los grupos
  #    permitidos, se permite sin llamadas extra.
  # 2. Si no (o hay "overage" de grupos), se pregunta a Graph con
  #    /me/checkMemberGroups (transitivo; basta el permiso delegado User.Read).
  # Si Graph falla, se niega el acceso (fail closed).
  class GroupGate
    Result = Struct.new(:allowed, :source, :reason, keyword_init: true) do
      def allowed? = allowed
    end

    def initialize(config, claims, graph)
      @config = config
      @claims = claims
      @graph = graph
    end

    def call
      return Result.new(allowed: true, source: :none) unless @config.restrict_by_group?

      allowed = @config.allowed_group_ids
      return Result.new(allowed: true, source: :claim) if claim_groups.intersect?(allowed)

      matches = @graph.member_of(allowed)
      if matches.intersect?(allowed)
        Result.new(allowed: true, source: :graph)
      else
        Result.new(allowed: false, source: :graph, reason: :not_in_allowed_group)
      end
    rescue OpenProject::EntraId::Http::Error => e
      Result.new(allowed: false, source: :graph, reason: :graph_error).tap do
        log_warn("Consulta de grupos en Graph falló: #{e.message}")
      end
    end

    private

    def claim_groups
      Array(@claims["groups"]).map { |id| id.to_s.downcase }
    end

    def log_warn(message)
      Rails.logger.warn("[entra_id] #{message}") if defined?(Rails)
    end
  end
end

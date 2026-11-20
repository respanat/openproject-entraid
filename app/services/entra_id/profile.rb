# frozen_string_literal: true

module EntraId
  ##
  # Datos del usuario combinando Graph /me (preferido) y los claims del id_token.
  class Profile
    attr_reader :external_id, :upn, :mail, :firstname, :lastname

    def initialize(claims, graph_me = {}, login_attribute: "upn")
      me = graph_me || {}
      @external_id = claims.fetch("oid").to_s.downcase
      @upn = presence(me["userPrincipalName"]) || presence(claims["preferred_username"]) || presence(claims["upn"])
      @mail = presence(me["mail"]) || presence(claims["email"]) || @upn
      @login_attribute = login_attribute

      first, last = split_name(presence(me["displayName"]) || presence(claims["name"]))
      @firstname = presence(me["givenName"]) || presence(claims["given_name"]) || first || local_part
      @lastname = presence(me["surname"]) || presence(claims["family_name"]) || last || "-"
    end

    def login
      (@login_attribute == "mail" ? mail : upn).to_s.downcase
    end

    def identity_url
      "#{OpenProject::EntraId::PROVIDER_SLUG}:#{external_id}"
    end

    def to_s = "#{login} (oid #{external_id})"

    private

    def split_name(full)
      return [nil, nil] if full.nil?

      parts = full.strip.split(/\s+/, 2)
      [parts[0], parts[1]]
    end

    def local_part
      upn.to_s.split("@").first
    end

    def presence(value)
      str = value.to_s.strip
      str.empty? ? nil : str
    end
  end
end

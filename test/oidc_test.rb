require "minitest/autorun"
require "openssl"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "open_project/entra_id"
require_relative "../app/services/entra_id/group_gate"
require_relative "../app/services/entra_id/profile"

TENANT = "11111111-2222-3333-4444-555555555555"
CLIENT = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
KEY = OpenSSL::PKey::RSA.generate(2048)
JWK = JWT::JWK.new(KEY, kid: "k1")
APP_KEY = OpenSSL::PKey::RSA.generate(2048)
APP_JWK = JWT::JWK.new(APP_KEY, kid: "app1")

class FakeHttp
  attr_reader :calls
  def initialize(groups: []) = (@calls = []; @groups = groups)
  def get_json(url, headers: {})
    @calls << url
    case url
    when /openid-configuration/ then { "issuer" => "https://login.microsoftonline.com/#{TENANT}/v2.0",
      "authorization_endpoint" => "https://login.microsoftonline.com/#{TENANT}/oauth2/v2.0/authorize",
      "token_endpoint" => "https://login.microsoftonline.com/#{TENANT}/oauth2/v2.0/token",
      "jwks_uri" => "https://login.microsoftonline.com/#{TENANT}/discovery/v2.0/keys" }
    when /keys\?appid=#{CLIENT}/ then { "keys" => [APP_JWK.export] }
    when /keys/ then { "keys" => [JWK.export] }
    end
  end
  def post_json(url, payload, headers: {}) = (@calls << url; { "value" => payload[:groupIds] & @groups })
end

def config(extra = {})
  OpenProject::EntraId::Configuration.new({ "enabled" => "1", "tenant_id" => TENANT.upcase, "client_id" => CLIENT, "client_secret" => "s" }.merge(extra))
end

def token(claims = {}, key: KEY, kid: "k1")
  now = Time.now.to_i
  payload = { "iss" => "https://login.microsoftonline.com/#{TENANT}/v2.0", "aud" => CLIENT, "tid" => TENANT,
              "oid" => "99999999-0000-0000-0000-000000000001", "nonce" => "n1", "iat" => now, "nbf" => now, "exp" => now + 600,
              "preferred_username" => "Ramiro@Contoso.com", "name" => "Ramiro España Tejada" }.merge(claims)
  JWT.encode(payload, key, "RS256", { kid: })
end

class OidcTest < Minitest::Test
  def setup = OpenProject::EntraId::OidcClient.clear_cache!
  def client(cfg = config) = OpenProject::EntraId::OidcClient.new(cfg, http: FakeHttp.new)

  def test_config
    assert config.usable?
    assert_equal TENANT, config.tenant_id
    refute config({ "tenant_id" => "common" }).usable?
    assert_equal [:allowed_group_ids], config({ "allowed_group_ids" => "x, y" }).configuration_errors
    c = OpenProject::EntraId::Configuration.new({ "client_secret" => "db" }, { "ENTRA_ID_CLIENT_SECRET" => "env" })
    assert_equal "env", c.client_secret
  end

  def test_valid_token = assert_equal "99999999-0000-0000-0000-000000000001", client.validate_id_token(token, nonce: "n1")["oid"]

  def test_auth_url
    url = client.authorization_url(redirect_uri: "https://op/entra_id/callback", state: "s", nonce: "n", code_verifier: "v" * 50)
    assert_match "code_challenge_method=S256", url
    assert_match "response_type=code", url
  end

  { "bad_nonce" => [{}, "other"], "other_tenant" => [{ "tid" => "00000000-0000-0000-0000-000000000000" }, "n1"],
    "bad_aud" => [{ "aud" => "x" }, "n1"], "expired" => [{ "exp" => Time.now.to_i - 1000 }, "n1"],
    "bad_iss" => [{ "iss" => "https://evil/v2.0" }, "n1"], "no_oid" => [{ "oid" => nil }, "n1"] }.each do |name, (claims, nonce)|
    define_method("test_rejects_#{name}") do
      assert_raises(OpenProject::EntraId::LoginError) { client.validate_id_token(token(claims), nonce:) }
    end
  end

  # Apps con SSO SAML firman el id_token con su propia llave (jwks_uri?appid=...).
  def test_accepts_app_specific_signing_key
    claims = client.validate_id_token(token({}, key: APP_KEY, kid: "app1"), nonce: "n1")
    assert_equal "99999999-0000-0000-0000-000000000001", claims["oid"]
  end

  def test_rejects_foreign_key
    assert_raises(OpenProject::EntraId::LoginError) { client.validate_id_token(token({}, key: OpenSSL::PKey::RSA.generate(2048)), nonce: "n1") }
  end

  def test_group_gate
    g1 = "aaaaaaaa-0000-0000-0000-000000000001"
    cfg = config({ "allowed_group_ids" => g1.upcase })
    http = FakeHttp.new(groups: [])
    graph = OpenProject::EntraId::GraphClient.new("t", http:)
    assert EntraId::GroupGate.new(cfg, { "groups" => [g1] }, graph).call.allowed?
    assert_empty http.calls
    refute EntraId::GroupGate.new(cfg, {}, graph).call.allowed?
    assert EntraId::GroupGate.new(cfg, {}, OpenProject::EntraId::GraphClient.new("t", http: FakeHttp.new(groups: [g1]))).call.allowed?
    assert EntraId::GroupGate.new(config, {}, graph).call.allowed?
  end

  def test_profile
    claims = JWT.decode(token, nil, false).first
    p = EntraId::Profile.new(claims, {})
    assert_equal ["ramiro@contoso.com", "Ramiro", "España Tejada", "entra_id:99999999-0000-0000-0000-000000000001"], [p.login, p.firstname, p.lastname, p.identity_url]
    p2 = EntraId::Profile.new(claims, { "givenName" => "R", "surname" => "E", "mail" => "r@x.co" }, login_attribute: "mail")
    assert_equal ["r@x.co", "R", "E"], [p2.login, p2.firstname, p2.lastname]
  end

  def test_logo_upload
    up = OpenProject::EntraId::LogoUpload
    png = "\x89PNG\r\n\x1A\n".b + "x" * 20
    assert up.to_data_uri(png).start_with?("data:image/png;base64,")
    svg = %(<?xml version="1.0"?>\n<svg xmlns="http://www.w3.org/2000/svg"><rect width="1" height="1"/></svg>)
    assert up.to_data_uri(svg).start_with?("data:image/svg+xml;base64,")
    err = ->(bytes) { assert_raises(up::Invalid) { up.to_data_uri(bytes) }.message }
    assert_equal "logo_bad_type", err.call("<html>hola</html>")
    assert_equal "logo_too_big", err.call(png + "x" * up::MAX_BYTES)
    assert_equal "logo_unsafe_svg", err.call(%(<svg><script>alert(1)</script></svg>))
    assert_equal "logo_unsafe_svg", err.call(%(<svg onload="x()"></svg>))
    assert_equal "logo_unsafe_svg", err.call(%(<svg><image href="https://evil/x.png"/></svg>))
    assert_equal "logo_empty", err.call("")
  end

  def test_appearance_settings
    assert_equal ["key", "visible"], [config.button_logo, config.local_login_mode]
    assert_equal "key", config({ "button_logo" => "custom" }).button_logo # sin logo subido
    c = config({ "button_logo" => "custom", "custom_logo" => "data:image/png;base64,AA==", "local_login_mode" => "hidden" })
    assert_equal ["custom", "hidden"], [c.button_logo, c.local_login_mode]
    assert_equal "", config({ "custom_logo" => "javascript:alert(1)" }).custom_logo
    assert_equal "visible", config({ "local_login_mode" => "raro" }).local_login_mode
  end
end

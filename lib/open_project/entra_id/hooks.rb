# frozen_string_literal: true

module OpenProject
  module EntraId
    # Añade el botón "Iniciar sesión con Microsoft" en la página de login
    # (mismo hook que usan los proveedores SSO del core).
    class Hooks < OpenProject::Hook::ViewListener
      render_on :view_account_login_auth_provider, partial: "hooks/entra_id/login_button"
    end
  end
end

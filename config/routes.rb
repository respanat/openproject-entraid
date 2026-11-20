# frozen_string_literal: true

Rails.application.routes.draw do
  get "/entra_id/login", to: "entra_id/sessions#login", as: :entra_id_login
  get "/entra_id/callback", to: "entra_id/sessions#callback", as: :entra_id_callback

  get "/admin/entra_id", to: "entra_id/settings#show", as: :entra_id_settings
  patch "/admin/entra_id", to: "entra_id/settings#update"
  post "/admin/entra_id/test", to: "entra_id/settings#test", as: :entra_id_settings_test
end

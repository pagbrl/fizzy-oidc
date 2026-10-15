Rails.application.routes.draw do
  match "/auth/:provider/callback",
    to: "fizzy/oidc/callbacks#create",
    via: [:get, :post],
    as: :fizzy_oidc_callback

  get "/auth/failure", to: "fizzy/oidc/callbacks#failure", as: :fizzy_oidc_failure

  post "/oidc/users", to: "fizzy/oidc/users#create", defaults: { format: :json }, as: :fizzy_oidc_users
end

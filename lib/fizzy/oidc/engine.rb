require "rails/engine"
require "omniauth"
require "omniauth_openid_connect"

module Fizzy
  module Oidc
    class Engine < ::Rails::Engine
      isolate_namespace Fizzy::Oidc

      config.fizzy_oidc = ActiveSupport::OrderedOptions.new

      initializer "fizzy_oidc.append_migrations" do |app|
        unless app.root.to_s.start_with?(root.to_s)
          config.paths["db/migrate"].expanded.each do |path|
            app.config.paths["db/migrate"] << path
            ActiveRecord::Migrator.migrations_paths << path
          end
        end
      end

      initializer "fizzy_oidc.middleware" do |app|
        cfg = Fizzy::Oidc.config
        app.middleware.use OmniAuth::Builder do
          provider :openid_connect,
            name: :fizzy_oidc,
            scope: cfg.scopes,
            response_type: :code,
            discovery: true,
            issuer: cfg.issuer,
            client_options: {
              identifier: cfg.client_id,
              secret: cfg.client_secret,
              redirect_uri: cfg.redirect_uri
            }
        end

        OmniAuth.config.path_prefix = "/auth"
        OmniAuth.config.request_validation_phase = Fizzy::Oidc::RequestValidation.new
        OmniAuth.config.failure_raise_out_environments = []
        OmniAuth.config.on_failure = ->(env) {
          Fizzy::Oidc::CallbacksController.action(:failure).call(env)
        }
      end

      rake_tasks do
        %w[db:prepare db:migrate db:schema:load].each do |name|
          next unless Rake::Task.task_defined?(name)

          Rake::Task[name].enhance { Fizzy::Oidc::Schema.ensure! }
        end
      end

      config.to_prepare do
        require "fizzy/oidc/patches/sessions_controller"
        require "fizzy/oidc/patches/signups_controller"
        require "fizzy/oidc/patches/magic_links_controller"
        require "fizzy/oidc/patches/completions_controller"
        require "fizzy/oidc/patches/passkeys_controller"

        SessionsController.prepend(Fizzy::Oidc::Patches::SessionsController)
        # Fizzy's CSP says form-action 'self', and browsers apply it to the
        # redirects that follow a form submission: the sign-in button's POST
        # would be stopped on its way to the IdP. Only this page needs it.
        SessionsController.content_security_policy do |policy|
          policy.form_action(*policy.directives.fetch("form-action", ["'self'"]), Fizzy::Oidc.config.issuer_origin)
        end
        SignupsController.prepend(Fizzy::Oidc::Patches::SignupsController)
        Sessions::MagicLinksController.prepend(Fizzy::Oidc::Patches::MagicLinksController)
        Signups::CompletionsController.prepend(Fizzy::Oidc::Patches::CompletionsController)
        Sessions::PasskeysController.prepend(Fizzy::Oidc::Patches::PasskeysController)
      end
    end
  end
end

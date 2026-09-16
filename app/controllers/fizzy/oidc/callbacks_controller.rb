module Fizzy
  module Oidc
    class CallbacksController < ApplicationController
      disallow_account_scope
      allow_unauthenticated_access
      skip_forgery_protection only: :create

      layout "public"

      def create
        auth = request.env["omniauth.auth"]
        if auth.blank?
          redirect_to main_app.new_session_path, alert: "OIDC sign-in failed." and return
        end

        claims = Claims.from_omniauth(auth)
        identity, _user, account = Provisioner.new(claims).call

        start_new_session_for(identity)
        redirect_to main_app.landing_url(script_name: account.slug)
      rescue ProvisioningError => error
        Rails.logger.warn("[fizzy-oidc] provisioning failed: #{error.message}")
        redirect_to main_app.new_session_path, alert: "OIDC sign-in could not be completed."
      rescue => error
        Rails.error.report(error, severity: :error)
        redirect_to main_app.new_session_path, alert: "Something went wrong signing in."
      end

      def failure
        message = request.env["omniauth.error.type"] || params[:message] || "unknown_error"
        Rails.logger.warn("[fizzy-oidc] omniauth failure: #{message}")
        redirect_to main_app.new_session_path, alert: "OIDC sign-in failed (#{message})."
      end
    end
  end
end

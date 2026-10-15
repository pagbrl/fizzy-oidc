module Fizzy
  module Oidc
    # OmniAuth 2 starts the request phase on POST only and asks a validator to
    # check the authenticity token, so a third-party page cannot log anyone in.
    #
    # Not omniauth-rails_csrf_protection: its TokenVerifier mimics a controller,
    # and Rails 8.2's verified_request? calls action_name, which it lacks (1.0.2
    # fails every login; 2.0.1 also stops Fizzy from booting, by loading
    # ActionController::Base at require time). The check runs in a real,
    # autoloaded controller instead, with the app's own forgery settings.
    class RequestValidation
      def call(env)
        ForgeryChecksController.action(:show).call(env)
      rescue ActionController::InvalidAuthenticityToken => error
        raise OmniAuth::AuthenticityError, error.message
      end
    end
  end
end

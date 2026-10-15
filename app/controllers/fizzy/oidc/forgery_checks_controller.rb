module Fizzy
  module Oidc
    # Never routed: RequestValidation calls it directly, for its before_action.
    class ForgeryChecksController < ActionController::Base
      protect_from_forgery with: :exception

      def show
        head :ok
      end
    end
  end
end

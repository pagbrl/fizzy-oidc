module Fizzy
  module Oidc
    module Patches
      module CompletionsController
        def new
          redirect_to "/auth/fizzy_oidc", allow_other_host: false
        end

        def create
          redirect_to "/auth/fizzy_oidc", allow_other_host: false
        end
      end
    end
  end
end

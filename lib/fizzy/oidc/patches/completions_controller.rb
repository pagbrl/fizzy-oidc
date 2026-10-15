module Fizzy
  module Oidc
    module Patches
      module CompletionsController
        def new
          redirect_to new_session_path
        end

        def create
          redirect_to new_session_path
        end
      end
    end
  end
end

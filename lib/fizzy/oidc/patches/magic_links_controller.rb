module Fizzy
  module Oidc
    module Patches
      module MagicLinksController
        def show
          redirect_to new_session_path
        end

        def create
          redirect_to new_session_path
        end
      end
    end
  end
end

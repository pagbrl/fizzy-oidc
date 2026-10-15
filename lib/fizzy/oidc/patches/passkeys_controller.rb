module Fizzy
  module Oidc
    module Patches
      module PasskeysController
        def create
          redirect_to new_session_path
        end
      end
    end
  end
end

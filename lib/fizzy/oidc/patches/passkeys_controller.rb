module Fizzy
  module Oidc
    module Patches
      module PasskeysController
        def create
          redirect_to "/auth/fizzy_oidc", allow_other_host: false
        end
      end
    end
  end
end

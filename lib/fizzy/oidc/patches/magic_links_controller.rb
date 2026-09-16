module Fizzy
  module Oidc
    module Patches
      module MagicLinksController
        def show
          redirect_to "/auth/fizzy_oidc", allow_other_host: false
        end

        def create
          redirect_to "/auth/fizzy_oidc", allow_other_host: false
        end
      end
    end
  end
end

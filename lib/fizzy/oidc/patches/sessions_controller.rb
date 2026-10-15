module Fizzy
  module Oidc
    module Patches
      module SessionsController
        # The sign-in page is one button that POSTs to the IdP. A redirect to
        # /auth/fizzy_oidc would be a GET, which OmniAuth 2 answers with a 404.
        def new
          render "fizzy/oidc/sessions/new"
        end

        def create
          redirect_to new_session_path
        end
      end
    end
  end
end

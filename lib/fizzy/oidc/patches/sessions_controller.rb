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

        def destroy
          id_token = Current.session.oidc_id_token
          terminate_session

          respond_to do |format|
            format.html do
              redirect_to Logout.url(id_token:, post_logout_redirect_uri: main_app.new_session_url(script_name: nil)) || logout_url,
                allow_other_host: true
            end
            format.json { head :no_content }
          end
        end
      end
    end
  end
end

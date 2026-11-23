module Fizzy
  module Oidc
    module Patches
      # Without a cache header the browser follows the redirect again on every
      # page. The owner is left out so a new photo shows to them at once.
      module AvatarsController
        def show
          super
          expires_in 5.minutes, public: false if response.redirect? && !@user.system? && @user != Current.user
        end
      end
    end
  end
end

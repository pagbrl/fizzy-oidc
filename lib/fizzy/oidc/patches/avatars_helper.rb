module Fizzy
  module Oidc
    module Patches
      module AvatarsHelper
        def avatar_image_tag(user, **options)
          super(user, loading: "lazy", **options)
        end
      end
    end
  end
end

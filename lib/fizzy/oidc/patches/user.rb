module Fizzy
  module Oidc
    module Patches
      module User
        extend ActiveSupport::Concern

        included do
          after_destroy { Fizzy::Oidc::GroupMembership.where(user_id: id).delete_all }
        end
      end
    end
  end
end

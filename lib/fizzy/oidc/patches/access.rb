module Fizzy
  module Oidc
    module Patches
      # Whatever removes an access (unticked, deactivated) also removes the
      # record that a group gave it, so a later access is not taken for one.
      module Access
        extend ActiveSupport::Concern

        included do
          after_destroy { Fizzy::Oidc::GroupGrant.where(board_id:, user_id:).delete_all }
        end
      end
    end
  end
end

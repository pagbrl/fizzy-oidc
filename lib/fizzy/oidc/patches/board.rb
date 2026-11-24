module Fizzy
  module Oidc
    module Patches
      # Fizzy deletes a board's accesses without callbacks.
      module Board
        extend ActiveSupport::Concern

        included do
          after_destroy do
            Fizzy::Oidc::BoardGroup.where(board_id: id).delete_all
            Fizzy::Oidc::GroupGrant.where(board_id: id).delete_all
          end
        end
      end
    end
  end
end

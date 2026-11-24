module Fizzy
  module Oidc
    class GroupGrant < ::ApplicationRecord
      self.table_name = "oidc_group_grants"

      belongs_to :board
      belongs_to :user
    end
  end
end

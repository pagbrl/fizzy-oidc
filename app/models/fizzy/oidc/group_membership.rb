module Fizzy
  module Oidc
    class GroupMembership < ::ApplicationRecord
      self.table_name = "oidc_group_memberships"

      belongs_to :group, class_name: "Fizzy::Oidc::Group"
      belongs_to :user
    end
  end
end

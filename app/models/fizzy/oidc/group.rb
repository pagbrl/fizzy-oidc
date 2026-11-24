module Fizzy
  module Oidc
    class Group < ::ApplicationRecord
      self.table_name = "oidc_groups"

      belongs_to :account
      has_many :memberships, class_name: "Fizzy::Oidc::GroupMembership", dependent: :delete_all
      has_many :board_groups, class_name: "Fizzy::Oidc::BoardGroup", dependent: :delete_all
    end
  end
end

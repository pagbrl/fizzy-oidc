module Fizzy
  module Oidc
    class BoardGroup < ::ApplicationRecord
      self.table_name = "oidc_board_groups"

      belongs_to :board
      belongs_to :group, class_name: "Fizzy::Oidc::Group"
    end
  end
end

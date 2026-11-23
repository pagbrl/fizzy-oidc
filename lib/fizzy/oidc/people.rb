module Fizzy
  module Oidc
    module People
      module_function

      def sharing_a_board_with(user)
        user.account.users.active.where(id: Access.where(board_id: user.accesses.select(:board_id)).select(:user_id))
      end
    end
  end
end

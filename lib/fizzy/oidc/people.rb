module Fizzy
  module Oidc
    module People
      SEARCH_LIMIT = 20

      module_function

      def sharing_a_board_with(user)
        user.account.users.active.where(id: Access.where(board_id: user.accesses.select(:board_id)).select(:user_id))
      end

      def addable_to(board, query)
        return User.none if query.blank?

        pattern = "%#{User.sanitize_sql_like(query.strip.downcase)}%"
        board.account.users.active
          .where.not(id: board.accesses.select(:user_id))
          .joins(:identity)
          .where("LOWER(users.name) LIKE :pattern OR LOWER(identities.email_address) LIKE :pattern", pattern:)
          .alphabetically
          .limit(SEARCH_LIMIT)
      end
    end
  end
end

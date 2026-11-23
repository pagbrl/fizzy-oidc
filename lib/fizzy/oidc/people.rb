module Fizzy
  module Oidc
    module People
      SEARCH_LIMIT = 20

      module_function

      def sharing_a_board_with(user)
        user.account.users.active.where(id: Access.where(board_id: user.accesses.select(:board_id)).select(:user_id))
      end

      def addable(board)
        board.account.users.active.where.not(id: board.accesses.select(:user_id))
      end

      # shortcut: folds every addable user in Ruby (about 3,600 in prod, a few ms); move to a stored folded column if accounts reach tens of thousands.
      # SQLite's LOWER() folds ASCII only and LIKE needs an ESCAPE clause, so the match is done here, as upstream's filterMatches did it in the browser.
      def addable_to(board, query)
        needle = fold(query)
        return User.none if needle.empty?

        ids = addable(board).joins(:identity).alphabetically.pluck(:id, :name, "identities.email_address")
          .select { |_, name, email| fold(name).include?(needle) || fold(email).include?(needle) }
          .first(SEARCH_LIMIT).map(&:first)
        User.where(id: ids).alphabetically
      end

      def fold(text)
        text.to_s.strip.downcase.unicode_normalize(:nfd).gsub(/[̀-ͯ]/, "")
      end
    end
  end
end

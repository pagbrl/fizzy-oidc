module Fizzy
  module Oidc
    module People
      SEARCH_LIMIT = 20

      module_function

      def assignees_of(cards)
        Assignment.where(card_id: cards.select(:id)).select(:assignee_id)
      end

      def creators_of(cards)
        cards.select(:creator_id)
      end

      def closers_of(cards)
        Closure.where(card_id: cards.select(:id)).select(:user_id)
      end

      # The Activity page filters its events by author, among these actions.
      def authors_on(board_ids)
        Event.where(board_id: board_ids, action: User::DayTimeline::TIMELINEABLE_ACTIONS).select(:creator_id)
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

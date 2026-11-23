module Fizzy
  module Oidc
    module Patches
      module MenusController
        def show
          @filters = Current.user.filters.all
          @boards = Current.user.boards.ordered_by_recently_accessed
          @tags = Current.account.tags.all.alphabetically
          @users = people_on(cards = Card.where(board_id: Current.user.accesses.select(:board_id)))
          @accounts = Current.identity.accounts.active

          # An assignment touches its card, so the cards' count and latest
          # update move whenever the people on them can.
          fresh_when etag: [ @filters, @boards, @tags, @users, cards, @accounts ]
        end

        private
          def people_on(cards)
            active = Current.account.users.active
            active.where(id: People.assignees_of(cards)).or(active.where(id: People.creators_of(cards))).alphabetically
          end
      end
    end
  end
end

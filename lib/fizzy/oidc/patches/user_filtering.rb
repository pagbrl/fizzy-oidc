module Fizzy
  module Oidc
    module Patches
      module UserFiltering
        # A board page shows its columns without putting the board in the
        # filter, so BoardsController#show hands it over.
        attr_writer :board

        # Each person filter offers who holds that role on a card in scope.
        # People already picked stay listed: the combobox only keeps the
        # items it renders.
        def assignee_choices
          @assignee_choices ||= choices(People.assignees_of(cards_in_scope), filter.assignees)
        end

        def creator_choices
          @creator_choices ||= choices(People.creators_of(cards_in_scope), filter.creators)
        end

        def closer_choices
          @closer_choices ||= choices(People.closers_of(cards_in_scope), filter.closers)
        end

        def users
          @users ||= assignee_choices.or(creator_choices).or(closer_choices)
        end

        # The lists follow the cards: an assignment or a closure touches its card.
        def cache_key
          ActiveSupport::Cache.expand_cache_key([ super, cards_in_scope ], "user-filtering")
        end

        private
          def cards_in_scope
            @cards_in_scope ||= Card.where(board_id: (@board || filter.single_board)&.id || user.accesses.select(:board_id))
          end

          def choices(ids, selected)
            active = account.users.active
            active.where(id: ids).or(active.where(id: selected.map(&:id))).alphabetically
          end
      end
    end
  end
end

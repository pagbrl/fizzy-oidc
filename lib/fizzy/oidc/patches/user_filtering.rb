module Fizzy
  module Oidc
    module Patches
      module UserFiltering
        # A board page shows its columns without putting the board in the
        # filter, so BoardsController#show hands it over.
        attr_writer :board

        # People already picked in the filter stay listed even when they no
        # longer share a board: the combobox only keeps the items it renders.
        def users
          @users ||= begin
            board = @board || filter.single_board
            people = board ? board.users.active : People.sharing_a_board_with(user)
            selected_ids = [ filter.assignees, filter.creators, filter.closers ].flat_map { |users| users.map(&:id) }
            active = account.users.active

            active.where(id: people.select(:id)).or(active.where(id: selected_ids)).alphabetically
          end
        end
      end
    end
  end
end

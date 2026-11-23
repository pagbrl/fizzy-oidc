module Fizzy
  module Oidc
    module Patches
      module BoardsController
        def show
          @user_filtering.board = @board
          super
        end

        # Lists the members, plus the people a search found, instead of the
        # whole account. Every member is still rendered as a checked toggle:
        # #update revokes whoever is a member and missing from user_ids.
        def edit
          @selected_users = @board.users.active.alphabetically.includes(:identity, :account)
          @unselected_users = People.addable_to(@board, params[:q]).includes(:identity)
        end
      end
    end
  end
end

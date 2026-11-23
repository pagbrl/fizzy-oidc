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
          @ticked_users = People.addable(@board).where(id: params[:user_ids]).alphabetically.includes(:identity)
          @unselected_users = People.addable_to(@board, params[:q]).where.not(id: @ticked_users.select(:id)).includes(:identity)
        end

        # The search button submits the board's form, so the people ticked
        # in an earlier search come back ticked. It never saves.
        def update
          if params[:search_people]
            edit
            render :edit
          else
            super
          end
        end
      end
    end
  end
end

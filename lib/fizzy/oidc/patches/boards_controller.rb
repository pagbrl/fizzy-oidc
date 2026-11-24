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
        # Members only an attached group lets in are listed apart, locked.
        def edit
          @granted_through = ProjectGroups.granted_through(@board)
          members = @board.users.active.alphabetically.includes(:identity, :account)
          @selected_users = members.where.not(id: @granted_through.keys)
          @group_users = members.where(id: @granted_through.keys)
          @ticked_users = People.addable(@board).where(id: params[:user_ids]).alphabetically.includes(:identity)
          @unselected_users = People.addable_to(@board, params[:q]).where.not(id: @ticked_users.select(:id)).includes(:identity)

          @board_groups = ProjectGroups.attached_to(@board)
          @ticked_groups = ProjectGroups.addable(@board).where(id: params[:group_ids]).order(:name)
          @unselected_groups = ProjectGroups.addable_to(@board, params[:group_q]).where.not(id: @ticked_groups.select(:id))
        end

        # The search buttons submit the board's form, so what was ticked in an
        # earlier search comes back ticked. They never save.
        #
        # On the page, a member only a group lets in is locked: unticking
        # them would last until their next login. Through the API, user_ids
        # wins, as the community manager knows memberships fresher than the
        # last login; personal_user_ids makes those accesses in person.
        # Groups change after upstream's save, which would otherwise revoke the
        # members a newly attached group just let in.
        def update
          if params[:search_people] || params[:search_groups]
            edit
            render :edit
          else
            if params.key?(:user_ids) && !request.format.json?
              params[:user_ids] = Array(params[:user_ids]) + ProjectGroups.granted_through(@board).keys
            end

            @board.class.transaction do
              super
              ProjectGroups.claim_in_person(@board, Array(params[:personal_user_ids])) if params.key?(:personal_user_ids)
              ProjectGroups.attach(@board, Array(params[:group_ids]).compact_blank) if params.key?(:group_ids)
            end
          end
        end
      end
    end
  end
end

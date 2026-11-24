module Fizzy
  module Oidc
    # The IdP's project groups, which a board's admins attach to it. Membership
    # is the groups claim at login. An attached group gives its members access,
    # and records the accesses it created (GroupGrant) so that only those are
    # taken back when the group goes or the member leaves it.
    module ProjectGroups
      SEARCH_LIMIT = 20

      module_function

      # Keycloak sends the full path ("/Projet X") when its mapper says so.
      def names_in(claim_groups)
        claim_groups.map { it.delete_prefix("/") }.grep(Fizzy::Oidc.config.project_group_pattern).uniq
      end

      def sync_member(user, claim_groups)
        group_ids = names_in(claim_groups).map { |name| Group.find_or_create_by!(account_id: user.account_id, name:).id }
        GroupMembership.where(user_id: user.id).where.not(group_id: group_ids).delete_all
        group_ids.each { GroupMembership.find_or_create_by!(group_id: it, user_id: user.id) }

        board_ids = BoardGroup.where(group_id: group_ids).pluck(:board_id).uniq
        Board.where(id: board_ids).each { grant(it, [ user ]) }
        revoke GroupGrant.where(user_id: user.id).where.not(board_id: board_ids)
      end

      def attach(board, group_ids)
        ActiveRecord::Base.transaction do
          group_ids = Group.where(account_id: board.account_id, id: group_ids).pluck(:id)
          BoardGroup.where(board_id: board.id).where.not(group_id: group_ids).delete_all
          group_ids.each { BoardGroup.find_or_create_by!(board_id: board.id, group_id: it) }

          covered = covered_users(board).to_a
          grant(board, covered)
          revoke GroupGrant.where(board_id: board.id).where.not(user_id: covered.map(&:id))
        end
      end

      def attached_to(board)
        Group.where(id: BoardGroup.where(board_id: board.id).select(:group_id)).order(:name)
      end

      # The members whose access only an attached group gives, with that group's names.
      def granted_through(board)
        GroupMembership.joins(:group)
          .where(group_id: BoardGroup.where(board_id: board.id).select(:group_id), user_id: GroupGrant.where(board_id: board.id).select(:user_id))
          .order("oidc_groups.name").pluck(:user_id, "oidc_groups.name")
          .group_by(&:first).transform_values { it.map(&:last) }
      end

      def group_user_ids(board)
        GroupGrant.where(board_id: board.id, user_id: board.accesses.select(:user_id)).pluck(:user_id)
      end

      # The access stays, and no group takes it back any more.
      def claim_in_person(board, user_ids)
        GroupGrant.where(board_id: board.id, user_id: user_ids).delete_all
      end

      def addable(board)
        Group.where(account_id: board.account_id).where.not(id: attached_to(board).select(:id))
      end

      def addable_to(board, query)
        needle = People.fold(query)
        return Group.none if needle.empty?

        ids = addable(board).order(:name).pluck(:id, :name).select { |_, name| People.fold(name).include?(needle) }.first(SEARCH_LIMIT).map(&:first)
        Group.where(id: ids).order(:name)
      end

      def covered_users(board)
        board.account.users.active.where(id: GroupMembership.where(group_id: BoardGroup.where(board_id: board.id).select(:group_id)).select(:user_id))
      end

      def grant(board, users)
        present = board.accesses.where(user_id: users.map(&:id)).pluck(:user_id)
        users.reject { present.include?(it.id) }.each do |user|
          Access.create!(board:, user:, account_id: board.account_id)
          GroupGrant.find_or_create_by!(board_id: board.id, user_id: user.id)
        end
      end

      # Fizzy never revokes on an all-access board (Board::Accessible#revoke_from):
      # there the access stays, and the grant goes, so it is in person from now on.
      def revoke(grants)
        grants.where(board_id: Board.where(all_access: false).select(:id)).each do |grant|
          Access.where(board_id: grant.board_id, user_id: grant.user_id).destroy_all
        end
        grants.delete_all
      end
    end
  end
end

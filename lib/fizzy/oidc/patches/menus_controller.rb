module Fizzy
  module Oidc
    module Patches
      module MenusController
        def show
          @filters = Current.user.filters.all
          @boards = Current.user.boards.ordered_by_recently_accessed
          @tags = Current.account.tags.all.alphabetically
          @users = People.sharing_a_board_with(Current.user).alphabetically
          @accounts = Current.identity.accounts.active

          fresh_when etag: [ @filters, @boards, @tags, @users, @accounts ]
        end
      end
    end
  end
end

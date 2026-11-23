module Fizzy
  module Oidc
    module Patches
      module BoardsController
        def show
          @user_filtering.board = @board
          super
        end
      end
    end
  end
end

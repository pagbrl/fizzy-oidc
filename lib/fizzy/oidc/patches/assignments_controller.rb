module Fizzy
  module Oidc
    module Patches
      # The picker's rows each ask `card.assignees.include?(user)`: on an
      # unloaded association that is one query per member of the board.
      module AssignmentsController
        def new
          super
          @card.assignees.load unless performed?
        end
      end
    end
  end
end

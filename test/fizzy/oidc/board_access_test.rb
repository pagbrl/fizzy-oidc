require "test_helper"
require "fizzy/oidc/patches/boards_controller"

class Fizzy::Oidc::BoardAccessTest < Minitest::Test
  class Controller
    attr_reader :params, :selected_users, :unselected_users

    def initialize(board, params)
      @board, @params = board, params
    end

    def edit
    end

    prepend Fizzy::Oidc::Patches::BoardsController
  end

  def setup
    super
    @account = Account.create!(name: "Acme")
    @board = @account.boards.create!(name: "Infra", creator_id: "x")
    @bob = person("Bob Martin", member: true)
    @alice = person("alice", member: true)
    person("Gone Martin", member: true, active: false)
    @carol = person("Carol Martin")
  end

  def test_the_members_are_listed_and_nobody_else_without_a_search
    access = edit

    assert_equal [ @alice, @bob ], access.selected_users.to_a
    assert_empty access.unselected_users.to_a
  end

  def test_a_search_adds_only_people_outside_the_board
    access = edit(q: "martin")

    assert_equal [ @alice, @bob ], access.selected_users.to_a
    assert_equal [ @carol ], access.unselected_users.to_a
  end

  private
    def edit(**params)
      Controller.new(@board, params).tap(&:edit)
    end

    def person(name, member: false, active: true)
      identity = Identity.create!(email_address: "#{name.parameterize}@example.com")
      @account.users.create!(name:, identity:, active:).tap do |user|
        Access.create!(user:, board: @board, account: @account) if member
      end
    end
end

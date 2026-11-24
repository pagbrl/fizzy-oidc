require "test_helper"
require "fizzy/oidc/patches/boards_controller"

class Fizzy::Oidc::BoardAccessTest < Minitest::Test
  class Controller
    attr_reader :params, :selected_users, :ticked_users, :unselected_users, :group_users, :granted_through,
      :board_groups, :ticked_groups, :unselected_groups, :rendered

    def initialize(board, params)
      @board, @params = board, params
    end

    def edit
    end

    # Upstream's update: whoever is a member and missing from user_ids loses access.
    def update
      @board.accesses.where.not(user_id: params[:user_ids]).destroy_all if params.key?(:user_ids)
    end

    def render(template)
      @rendered = template
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

  def test_people_ticked_in_an_earlier_search_come_back_ticked
    dan = person("Dan")
    access = edit(q: "martin", user_ids: [ @alice.id, @bob.id, dan.id ])

    assert_equal [ dan ], access.ticked_users.to_a
    assert_equal [ @carol ], access.unselected_users.to_a
  end

  def test_a_ticked_person_found_again_is_listed_once_ticked
    access = edit(q: "martin", user_ids: [ @alice.id, @bob.id, @carol.id ])

    assert_equal [ @carol ], access.ticked_users.to_a
    assert_empty access.unselected_users.to_a
  end

  def test_a_member_only_an_attached_group_covers_is_listed_apart_with_the_group
    dan = person("Dan")
    Fizzy::Oidc::GroupMembership.create!(group: alpha, user: dan)
    Fizzy::Oidc::ProjectGroups.attach(@board, [ alpha.id ])

    access = edit

    assert_equal [ @alice, @bob ], access.selected_users.to_a
    assert_equal [ dan ], access.group_users.to_a
    assert_equal({ dan.id => [ "Projet Alpha" ] }, access.granted_through)
    assert_equal [ alpha ], access.board_groups.to_a
  end

  def test_unticking_a_member_only_a_group_covers_keeps_them
    dan = person("Dan")
    Fizzy::Oidc::GroupMembership.create!(group: alpha, user: dan)
    Fizzy::Oidc::ProjectGroups.attach(@board, [ alpha.id ])

    update(user_ids: [ @alice.id.to_s ], group_ids: [ "", alpha.id.to_s ])

    assert_equal [ @alice, dan ], @board.reload.users.alphabetically.to_a
  end

  def test_saving_attaches_and_detaches_the_ticked_groups
    dan = person("Dan")
    Fizzy::Oidc::GroupMembership.create!(group: alpha, user: dan)

    update(user_ids: [ @alice.id, @bob.id ], group_ids: [ "", alpha.id.to_s ])
    assert_includes @board.reload.users, dan

    update(user_ids: [ @alice.id, @bob.id ], group_ids: [ "" ])
    refute_includes @board.reload.users, dan
    assert_equal [ @alice, @bob ], @board.users.alphabetically.to_a
  end

  def test_a_save_without_group_ids_leaves_the_groups_alone
    Fizzy::Oidc::ProjectGroups.attach(@board, [ alpha.id ])

    update(user_ids: [ @alice.id, @bob.id ])

    assert_equal [ alpha.id ], Fizzy::Oidc::BoardGroup.where(board_id: @board.id).pluck(:group_id)
  end

  def test_a_group_search_lists_the_groups_ticked_earlier_and_the_ones_found
    beta = Fizzy::Oidc::Group.create!(account: @account, name: "Projet Beta")
    gamma = Fizzy::Oidc::Group.create!(account: @account, name: "Projet Bêta-test")

    access = update(group_q: "beta", search_groups: "1", group_ids: [ "", beta.id.to_s ])

    assert_equal :edit, access.rendered
    assert_equal [ beta ], access.ticked_groups.to_a
    assert_equal [ gamma ], access.unselected_groups.to_a
    assert_empty Fizzy::Oidc::BoardGroup.all
  end

  private
    def edit(**params)
      Controller.new(@board, params).tap(&:edit)
    end

    def update(**params)
      Controller.new(@board, params).tap(&:update)
    end

    def alpha
      @alpha ||= Fizzy::Oidc::Group.create!(account: @account, name: "Projet Alpha")
    end

    def person(name, member: false, active: true)
      identity = Identity.create!(email_address: "#{name.parameterize}@example.com")
      @account.users.create!(name:, identity:, active:).tap do |user|
        Access.create!(user:, board: @board, account: @account) if member
      end
    end
end

require "test_helper"
require "fizzy/oidc/patches/boards_controller"

class Fizzy::Oidc::BoardAccessTest < Minitest::Test
  class Controller
    attr_reader :params, :selected_users, :ticked_users, :unselected_users, :group_users, :granted_through,
      :board_groups, :locked_group_ids, :ticked_groups, :unselected_groups, :rendered

    def initialize(board, params, format: :html)
      @board, @params, @format = board, params, format
    end

    def request
      OpenStruct.new(format: OpenStruct.new(json?: @format == :json))
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
    Current.user = @viewer = person("Vera Admin", member: true, role: "admin")
  end

  def test_the_members_are_listed_and_nobody_else_without_a_search
    access = edit

    assert_equal [ @alice, @bob, @viewer ], access.selected_users.to_a
    assert_empty access.unselected_users.to_a
  end

  def test_a_search_adds_only_people_outside_the_board
    access = edit(q: "martin")

    assert_equal [ @alice, @bob, @viewer ], access.selected_users.to_a
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

    assert_equal [ @alice, @bob, @viewer ], access.selected_users.to_a
    assert_equal [ dan ], access.group_users.to_a
    assert_equal({ dan.id => [ "Projet Alpha" ] }, access.granted_through)
    assert_equal [ alpha ], access.board_groups.to_a
  end

  def test_unticking_a_member_only_a_group_covers_keeps_them
    dan = person("Dan")
    Fizzy::Oidc::GroupMembership.create!(group: alpha, user: dan)
    Fizzy::Oidc::ProjectGroups.attach(@board, [ alpha.id ])

    join(alpha)
    update(user_ids: [ @alice.id.to_s, @viewer.id.to_s ], group_ids: [ "", alpha.id.to_s ])

    assert_equal [ @alice, dan, @viewer ], @board.reload.users.alphabetically.to_a
  end

  def test_saving_attaches_and_detaches_the_ticked_groups
    dan = person("Dan")
    Fizzy::Oidc::GroupMembership.create!(group: alpha, user: dan)
    join(alpha)

    update(user_ids: [ @alice.id, @bob.id, @viewer.id ], group_ids: [ "", alpha.id.to_s ])
    assert_includes @board.reload.users, dan

    update(user_ids: [ @alice.id, @bob.id, @viewer.id ], group_ids: [ "" ])
    refute_includes @board.reload.users, dan
    assert_equal [ @alice, @bob, @viewer ], @board.users.alphabetically.to_a
  end

  def test_a_json_save_revokes_a_member_only_a_group_covers_when_user_ids_leaves_them_out
    dan = in_alpha("Dan")

    update_json(user_ids: [ @alice.id, @bob.id ])

    refute_includes @board.reload.users, dan
    assert_empty Fizzy::Oidc::GroupGrant.where(board_id: @board.id)
  end

  def test_a_json_save_makes_the_personal_user_ids_accesses_in_person
    dan = in_alpha("Dan")
    eve = in_alpha("Eve")

    update_json(user_ids: [ @alice.id, @bob.id, dan.id, eve.id ], personal_user_ids: [ dan.id.to_s, @carol.id.to_s ])

    assert_equal [ eve.id ], Fizzy::Oidc::GroupGrant.where(board_id: @board.id).pluck(:user_id)
    refute_includes @board.reload.users, @carol
  end

  def test_an_access_claimed_in_person_survives_leaving_the_group_at_login
    dan = in_alpha("Dan")
    update_json(user_ids: [ @alice.id, @bob.id, dan.id ], personal_user_ids: [ dan.id ])

    auth = build_auth(sub: "dan", email: dan.identity.email_address, name: "Dan", groups: [])
    Fizzy::Oidc::Provisioner.new(Fizzy::Oidc::Claims.from_omniauth(auth)).call

    assert_includes @board.reload.users, dan
  end

  def test_a_save_without_group_ids_leaves_the_groups_alone
    Fizzy::Oidc::ProjectGroups.attach(@board, [ alpha.id ])

    update(user_ids: [ @alice.id, @bob.id ])

    assert_equal [ alpha.id ], Fizzy::Oidc::BoardGroup.where(board_id: @board.id).pluck(:group_id)
  end

  def test_a_group_search_lists_the_groups_ticked_earlier_and_the_ones_found
    beta = Fizzy::Oidc::Group.create!(account: @account, name: "Projet Beta")
    gamma = Fizzy::Oidc::Group.create!(account: @account, name: "Projet Bêta-test")
    join(beta, gamma)

    access = update(group_q: "beta", search_groups: "1", group_ids: [ "", beta.id.to_s ])

    assert_equal :edit, access.rendered
    assert_equal [ beta ], access.ticked_groups.to_a
    assert_equal [ gamma ], access.unselected_groups.to_a
    assert_empty Fizzy::Oidc::BoardGroup.all
  end

  # Project groups are private: only their members see them offered.
  def test_only_the_viewers_own_groups_are_offered_with_or_without_a_search
    beta, gamma = group("Projet Beta"), group("Projet Gamma")
    join(alpha, gamma)

    assert_equal [ alpha, gamma ], edit.unselected_groups.to_a
    assert_equal [ alpha, gamma ], edit(group_q: "projet").unselected_groups.to_a
    assert_empty edit(group_q: "beta").unselected_groups.to_a
    refute_includes edit.unselected_groups.to_a, beta
  end

  def test_a_group_the_viewer_is_not_in_does_not_come_back_ticked_from_a_search
    join(alpha)
    beta = group("Projet Beta")

    access = update(group_q: "projet", search_groups: "1", group_ids: [ "", alpha.id.to_s, beta.id.to_s ])

    assert_equal [ alpha ], access.ticked_groups.to_a
    assert_empty access.unselected_groups.to_a
  end

  def test_an_attached_group_the_viewer_is_not_in_is_listed_locked
    beta = group("Projet Beta")
    join(alpha)
    Fizzy::Oidc::ProjectGroups.attach(@board, [ alpha.id, beta.id ])

    access = edit

    assert_equal [ alpha, beta ], access.board_groups.to_a
    assert_equal [ beta.id ], access.locked_group_ids
  end

  def test_a_save_without_an_attached_group_the_viewer_is_not_in_keeps_it
    dan = in_alpha("Dan")

    update(user_ids: [ @alice.id, @bob.id, @viewer.id ], group_ids: [ "" ])

    assert_equal [ alpha.id ], Fizzy::Oidc::BoardGroup.where(board_id: @board.id).pluck(:group_id)
    assert_includes @board.reload.users, dan
  end

  def test_a_forged_group_the_viewer_is_not_in_is_not_attached
    beta = group("Projet Beta")
    join(beta)
    Fizzy::Oidc::GroupMembership.create!(group: alpha, user: @carol)

    update(user_ids: [ @alice.id, @bob.id, @viewer.id ], group_ids: [ "", alpha.id.to_s, beta.id.to_s ])

    assert_equal [ beta.id ], Fizzy::Oidc::BoardGroup.where(board_id: @board.id).pluck(:group_id)
    refute_includes @board.reload.users, @carol
  end

  def test_the_owner_follows_the_same_rule
    @viewer.update!(role: "owner")
    beta = group("Projet Beta")
    Fizzy::Oidc::ProjectGroups.attach(@board, [ alpha.id ])

    access = edit(group_q: "projet")
    assert_empty access.unselected_groups.to_a
    assert_equal [ alpha.id ], access.locked_group_ids

    update(user_ids: [ @alice.id, @bob.id, @viewer.id ], group_ids: [ "", beta.id.to_s ])
    assert_equal [ alpha.id ], Fizzy::Oidc::BoardGroup.where(board_id: @board.id).pluck(:group_id)
  end

  private
    def edit(**params)
      Controller.new(@board, params).tap(&:edit)
    end

    def update(**params)
      Controller.new(@board, params).tap(&:update)
    end

    def update_json(**params)
      Controller.new(@board, params, format: :json).tap(&:update)
    end

    def in_alpha(name)
      person(name).tap do |user|
        Fizzy::Oidc::GroupMembership.create!(group: alpha, user:)
        Fizzy::Oidc::ProjectGroups.attach(@board, [ alpha.id ])
      end
    end

    def alpha
      @alpha ||= group("Projet Alpha")
    end

    def group(name)
      Fizzy::Oidc::Group.create!(account: @account, name:)
    end

    def join(*groups)
      groups.each { Fizzy::Oidc::GroupMembership.create!(group: it, user: @viewer) }
    end

    def person(name, member: false, active: true, role: "member")
      identity = Identity.create!(email_address: "#{name.parameterize}@example.com")
      @account.users.create!(name:, identity:, active:, role:).tap do |user|
        Access.create!(user:, board: @board, account: @account) if member
      end
    end
end

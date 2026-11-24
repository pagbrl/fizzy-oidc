require "test_helper"

class Fizzy::Oidc::ProjectGroupsTest < Minitest::Test
  Group = Fizzy::Oidc::Group
  ProjectGroups = Fizzy::Oidc::ProjectGroups

  def setup
    super
    log_in "owner", []
    @account = Account.first
    @board = @account.boards.create!(name: "Infra")
  end

  def test_a_login_sets_the_memberships_to_the_project_groups_of_the_claim
    alice = log_in "alice", [ "Projet Alpha", "/Projet Beta", "Projet Alpha Admin", "fizzy-admins", "Bénévoles" ]

    assert_equal [ "Projet Alpha", "Projet Beta" ], group_names(alice)

    log_in "alice", [ "Projet Beta", "Projet Gamma" ]

    assert_equal [ "Projet Beta", "Projet Gamma" ], group_names(alice)
    assert_equal [ "Projet Alpha", "Projet Beta", "Projet Gamma" ], Group.where(account: @account).order(:name).pluck(:name)
  end

  def test_the_project_group_pattern_comes_from_the_mapping
    write_mapping(<<~YAML)
      mappings:
        project_group_pattern: '\\Ateam-'
    YAML

    alice = log_in "alice", [ "team-red", "Projet Alpha" ]

    assert_equal [ "team-red" ], group_names(alice)
  end

  def test_attaching_a_group_grants_its_members_and_records_the_grants
    alice = log_in "alice", [ "Projet Alpha" ]
    bob = log_in "bob", [ "Projet Beta" ]

    attach "Projet Alpha"

    assert_equal [ alice ], board_users - [ owner ]
    assert_equal [ alice.id ], granted_user_ids
    refute_includes board_users, bob
  end

  def test_a_member_who_joins_an_attached_group_gets_access_at_login
    Group.create!(account: @account, name: "Projet Alpha")
    attach "Projet Alpha"

    alice = log_in "alice", [ "Projet Alpha" ]

    assert_includes board_users, alice
    assert_equal [ alice.id ], granted_user_ids
  end

  def test_detaching_revokes_only_the_grants_no_other_attached_group_covers
    alice = log_in "alice", [ "Projet Alpha" ]
    bob = log_in "bob", [ "Projet Alpha", "Projet Beta" ]
    attach "Projet Alpha", "Projet Beta"

    attach "Projet Beta"

    refute_includes board_users, alice
    assert_includes board_users, bob
    assert_equal [ bob.id ], granted_user_ids
  end

  def test_leaving_a_project_at_login_revokes_its_grants
    alice = log_in "alice", [ "Projet Alpha" ]
    attach "Projet Alpha"

    log_in "alice", []

    refute_includes board_users, alice
    assert_empty granted_user_ids
  end

  def test_leaving_one_project_keeps_access_another_attached_group_gives
    alice = log_in "alice", [ "Projet Alpha", "Projet Beta" ]
    attach "Projet Alpha", "Projet Beta"

    log_in "alice", [ "Projet Beta" ]

    assert_includes board_users, alice
  end

  def test_an_access_given_in_person_is_never_recorded_nor_removed
    alice = log_in "alice", [ "Projet Alpha" ]
    Access.create!(user: alice, board: @board, account: @account)

    attach "Projet Alpha"
    assert_empty granted_user_ids

    attach
    log_in "alice", []

    assert_includes board_users, alice
  end

  def test_an_all_access_board_keeps_everyone_when_a_group_goes
    alice = log_in "alice", [ "Projet Alpha" ]
    attach "Projet Alpha"
    @board.update!(all_access: true)

    attach

    assert_includes board_users, alice
  end

  def test_a_deactivated_member_is_not_granted
    alice = log_in "alice", [ "Projet Alpha" ]
    alice.update!(active: false)

    attach "Projet Alpha"

    refute_includes board_users, alice
  end

  def test_groups_of_another_account_cannot_be_attached
    other = Account.create!(name: "Other")
    stranger = Group.create!(account: other, name: "Projet Alpha")

    ProjectGroups.attach(@board, [ stranger.id ])

    assert_empty Fizzy::Oidc::BoardGroup.where(board_id: @board.id)
  end

  def test_removing_an_access_forgets_its_grant
    alice = log_in "alice", [ "Projet Alpha" ]
    attach "Projet Alpha"

    Access.find_by(user: alice, board: @board).destroy!

    assert_empty granted_user_ids
  end

  def test_destroying_a_board_or_a_user_drops_their_rows
    alice = log_in "alice", [ "Projet Alpha" ]
    attach "Projet Alpha"

    @board.destroy!
    assert_empty Fizzy::Oidc::BoardGroup.all
    assert_empty Fizzy::Oidc::GroupGrant.all

    alice.destroy!
    assert_empty Fizzy::Oidc::GroupMembership.all
  end

  def test_granted_through_names_the_groups_behind_each_group_only_member
    alice = log_in "alice", [ "Projet Alpha", "Projet Beta" ]
    bob = log_in "bob", [ "Projet Alpha" ]
    Access.create!(user: bob, board: @board, account: @account)
    attach "Projet Alpha", "Projet Beta"

    assert_equal({ alice.id => [ "Projet Alpha", "Projet Beta" ] }, ProjectGroups.granted_through(@board))
  end

  def test_a_search_finds_groups_not_yet_attached_by_name
    %w[ Alpha Alphonse Beta ].each { |name| Group.create!(account: @account, name: "Projet #{name}") }
    attach "Projet Alpha"

    assert_equal [ "Projet Alphonse" ], ProjectGroups.addable_to(@board, "alph").pluck(:name)
    assert_empty ProjectGroups.addable_to(@board, " ")
  end

  private
    def log_in(name, groups)
      auth = build_auth(sub: name, email: "#{name}@example.com", name: name.capitalize, groups:)
      Fizzy::Oidc::Provisioner.new(Fizzy::Oidc::Claims.from_omniauth(auth)).call[1]
    end

    def owner
      @account.users.find_by!(role: "owner")
    end

    def attach(*names)
      ProjectGroups.attach(@board, Group.where(account: @account, name: names).ids)
    end

    def group_names(user)
      Group.joins(:memberships).where(oidc_group_memberships: { user_id: user.id }).order(:name).pluck(:name)
    end

    def board_users
      @board.reload.users.to_a
    end

    def granted_user_ids
      Fizzy::Oidc::GroupGrant.where(board_id: @board.id).pluck(:user_id).sort
    end
end

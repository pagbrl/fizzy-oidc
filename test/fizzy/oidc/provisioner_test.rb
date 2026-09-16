require "test_helper"

class Fizzy::Oidc::ProvisionerTest < Minitest::Test
  def setup
    super
    write_mapping(<<~YAML)
      account:
        name: "Acme"
      mappings:
        admin_group: "fizzy-admins"
        default_boards: ["General"]
        groups:
          eng-team: { boards: ["Backend", "Infra"] }
          design:   { boards: ["Design"] }
    YAML
  end

  def test_first_login_bootstraps_account_and_makes_owner
    claims = claims_for(sub: "u1", email: "alice@example.com", name: "Alice", groups: %w[])

    identity, user, account = Fizzy::Oidc::Provisioner.new(claims).call

    assert_equal "Acme", account.name
    assert_equal "alice@example.com", identity.email_address
    assert_equal "u1", identity.oidc_subject
    assert_equal "oidc", identity.oidc_provider
    assert_equal "owner", user.role
    assert user.verified?
    assert_equal 2, account.users.count
  end

  def test_subsequent_login_creates_member
    Fizzy::Oidc::Provisioner.new(claims_for(sub: "u1", email: "alice@example.com", name: "Alice")).call

    _, user, _ = Fizzy::Oidc::Provisioner.new(claims_for(sub: "u2", email: "bob@example.com", name: "Bob")).call

    assert_equal "member", user.role
  end

  def test_admin_group_grants_admin_role
    Fizzy::Oidc::Provisioner.new(claims_for(sub: "u1", email: "alice@example.com")).call

    _, user, _ = Fizzy::Oidc::Provisioner.new(
      claims_for(sub: "u2", email: "bob@example.com", groups: %w[fizzy-admins])
    ).call

    assert_equal "admin", user.role
  end

  def test_admin_demoted_back_to_member_when_group_removed
    Fizzy::Oidc::Provisioner.new(claims_for(sub: "u1", email: "alice@example.com")).call
    Fizzy::Oidc::Provisioner.new(claims_for(sub: "u2", email: "bob@example.com", groups: %w[fizzy-admins])).call

    _, user, _ = Fizzy::Oidc::Provisioner.new(claims_for(sub: "u2", email: "bob@example.com", groups: [])).call

    assert_equal "member", user.role
  end

  def test_owner_never_demoted
    _, owner, _ = Fizzy::Oidc::Provisioner.new(claims_for(sub: "u1", email: "alice@example.com", groups: [])).call

    assert_equal "owner", owner.role

    _, owner_again, _ = Fizzy::Oidc::Provisioner.new(claims_for(sub: "u1", email: "alice@example.com", groups: [])).call

    assert_equal "owner", owner_again.role
  end

  def test_default_boards_granted_to_every_user
    account = seed_account_with_boards(["General", "Backend", "Infra", "Design"])

    _, user, _ = Fizzy::Oidc::Provisioner.new(claims_for(sub: "u1", email: "alice@example.com")).call

    assert_includes user.boards.pluck(:name), "General"
  end

  def test_group_mapping_grants_matching_boards
    seed_account_with_boards(["General", "Backend", "Infra", "Design"])

    _, user, _ = Fizzy::Oidc::Provisioner.new(
      claims_for(sub: "u1", email: "alice@example.com", groups: %w[eng-team])
    ).call

    assert_equal %w[Backend General Infra], user.boards.pluck(:name).sort
  end

  def test_removing_group_revokes_board_access
    seed_account_with_boards(["General", "Backend", "Infra", "Design"])

    Fizzy::Oidc::Provisioner.new(claims_for(sub: "u1", email: "alice@example.com", groups: %w[eng-team])).call
    _, user, _ = Fizzy::Oidc::Provisioner.new(claims_for(sub: "u1", email: "alice@example.com", groups: %w[design])).call

    names = user.boards.pluck(:name).sort
    assert_includes names, "General"
    assert_includes names, "Design"
    refute_includes names, "Backend"
    refute_includes names, "Infra"
  end

  def test_all_access_boards_untouched_by_reconciler
    account = seed_account_with_boards(["General", "Backend"])
    manual = account.boards.create!(name: "Open", all_access: true)

    _, user, _ = Fizzy::Oidc::Provisioner.new(claims_for(sub: "u1", email: "alice@example.com", groups: %w[eng-team])).call
    Access.create!(user: user, board: manual, account: account)

    _, user, _ = Fizzy::Oidc::Provisioner.new(claims_for(sub: "u1", email: "alice@example.com", groups: [])).call

    assert_includes user.boards.pluck(:name), "Open"
  end

  def test_unknown_mapped_boards_are_skipped_not_created
    seed_account_with_boards(["General"])

    _, user, _ = Fizzy::Oidc::Provisioner.new(
      claims_for(sub: "u1", email: "alice@example.com", groups: %w[eng-team])
    ).call

    assert_equal %w[General], user.boards.pluck(:name)
    assert_equal 1, Board.count
  end

  def test_identity_matched_by_email_fallback_updates_oidc_subject
    Fizzy::Oidc::Provisioner.new(claims_for(sub: "u1", email: "alice@example.com")).call

    existing = Identity.find_by(email_address: "alice@example.com")
    existing.update!(oidc_subject: nil, oidc_provider: nil)

    identity, _, _ = Fizzy::Oidc::Provisioner.new(claims_for(sub: "new-sub", email: "alice@example.com")).call

    assert_equal existing.id, identity.id
    assert_equal "new-sub", identity.reload.oidc_subject
  end

  private
    def claims_for(sub:, email:, name: nil, groups: [])
      Fizzy::Oidc::Claims.from_omniauth(build_auth(sub: sub, email: email, name: name, groups: groups))
    end

    def seed_account_with_boards(names)
      account = Account.create!(name: "Acme")
      account.users.create!(role: "system", name: "System", active: true)
      names.each { |n| account.boards.create!(name: n) }
      account
    end
end

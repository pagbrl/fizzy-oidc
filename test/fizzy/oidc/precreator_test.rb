require "test_helper"

class Fizzy::Oidc::PrecreatorTest < Minitest::Test
  def setup
    super
    write_mapping(<<~YAML)
      account:
        name: "Acme"
      mappings:
        admin_group: "fizzy-admins"
    YAML
    Fizzy::Oidc::Provisioner.new(claims_for(sub: "owner", email: "owner@example.com", name: "Owner")).call
    @account = Account.first
  end

  def test_creates_a_verified_member_without_oidc_subject
    user, created = Fizzy::Oidc::Precreator.new(@account, email: " Bob@Example.com ", name: "Bob").call

    assert created
    assert_equal "member", user.role
    assert_equal "Bob", user.name
    assert user.verified?
    assert_equal "bob@example.com", user.identity.email_address
    assert_nil user.identity.oidc_subject
  end

  def test_is_idempotent
    first, _ = Fizzy::Oidc::Precreator.new(@account, email: "bob@example.com", name: "Bob").call
    second, created = Fizzy::Oidc::Precreator.new(@account, email: "bob@example.com", name: "Robert").call

    refute created
    assert_equal first.id, second.id
    assert_equal "Bob", second.name
    assert_equal 1, Identity.where(email_address: "bob@example.com").count
  end

  def test_first_login_reuses_the_precreated_user_and_its_accesses
    user, _ = Fizzy::Oidc::Precreator.new(@account, email: "bob@example.com", name: "Bob").call
    board = @account.boards.create!(name: "Projet Alpha", all_access: false)
    Access.create!(user: user, board: board, account: @account)

    identity, logged_in, _ = Fizzy::Oidc::Provisioner.new(
      claims_for(sub: "bob-sub", email: "bob@example.com", name: "Bob", groups: ["fizzy-admins"])
    ).call

    assert_equal user.id, logged_in.id
    assert_equal "bob-sub", identity.oidc_subject
    assert_equal "admin", logged_in.reload.role
    assert_equal [board.id], logged_in.boards.pluck(:id)
    assert_equal 1, @account.users.where(identity: identity).count
  end

  def test_returns_a_user_who_already_logged_in
    _, existing, _ = Fizzy::Oidc::Provisioner.new(claims_for(sub: "bob-sub", email: "bob@example.com", name: "Bob")).call

    user, created = Fizzy::Oidc::Precreator.new(@account, email: "bob@example.com", name: "Bob").call

    refute created
    assert_equal existing.id, user.id
    assert_equal "bob-sub", user.identity.oidc_subject
  end

  def test_rejects_a_blank_email
    assert_raises(Fizzy::Oidc::ProvisioningError) do
      Fizzy::Oidc::Precreator.new(@account, email: " ", name: "Nobody").call
    end
  end

  private
    def claims_for(**kwargs)
      Fizzy::Oidc::Claims.from_omniauth(build_auth(**kwargs))
    end
end

require "test_helper"

class Fizzy::Oidc::ClaimsTest < Minitest::Test
  def test_parses_standard_omniauth_hash
    auth = build_auth(sub: "abc-123", email: "Jane@Example.com", name: "Jane Doe", groups: %w[eng admin])

    claims = Fizzy::Oidc::Claims.from_omniauth(auth)

    assert_equal "abc-123", claims.subject
    assert_equal "jane@example.com", claims.email
    assert_equal "Jane Doe", claims.name
    assert_equal %w[eng admin], claims.groups
  end

  def test_falls_back_to_email_when_name_missing
    auth = build_auth(sub: "s", email: "noname@example.com", name: nil)

    claims = Fizzy::Oidc::Claims.from_omniauth(auth)

    assert_equal "noname@example.com", claims.name
  end

  def test_reads_groups_from_configured_claim
    ENV["FIZZY_OIDC_GROUPS_CLAIM"] = "roles"
    reset_config

    auth = build_auth(sub: "s", email: "a@b.c", groups: %w[admin], groups_claim: "roles")

    claims = Fizzy::Oidc::Claims.from_omniauth(auth)

    assert_equal %w[admin], claims.groups
  ensure
    ENV.delete("FIZZY_OIDC_GROUPS_CLAIM")
    reset_config
  end

  def test_raises_when_sub_missing
    auth = build_auth(sub: nil, email: "a@b.c")

    assert_raises(Fizzy::Oidc::ProvisioningError) { Fizzy::Oidc::Claims.from_omniauth(auth) }
  end

  def test_raises_when_email_missing
    auth = build_auth(sub: "s", email: nil)

    assert_raises(Fizzy::Oidc::ProvisioningError) { Fizzy::Oidc::Claims.from_omniauth(auth) }
  end
end

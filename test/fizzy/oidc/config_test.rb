require "test_helper"

class Fizzy::Oidc::ConfigTest < Minitest::Test
  def test_reads_oidc_env
    assert_equal "https://id.test", Fizzy::Oidc.config.issuer
    assert_equal "client", Fizzy::Oidc.config.client_id
    assert_equal "secret", Fizzy::Oidc.config.client_secret
    assert_equal %w[openid email profile groups], Fizzy::Oidc.config.scopes
  end

  def test_issuer_origin_drops_the_path_and_a_default_port
    ENV["FIZZY_OIDC_ISSUER"] = "https://auth.example.org/realms/acme"
    assert_equal "https://auth.example.org", Fizzy::Oidc.config.issuer_origin

    ENV["FIZZY_OIDC_ISSUER"] = "http://localhost:8080/realms/acme"
    assert_equal "http://localhost:8080", Fizzy::Oidc.config.issuer_origin
  end

  def test_loads_account_name_from_yaml
    write_mapping(<<~YAML)
      account:
        name: "Acme"
    YAML

    assert_equal "Acme", Fizzy::Oidc.config.account_name
  end

  def test_falls_back_to_env_account_name
    ENV["FIZZY_OIDC_ACCOUNT_NAME"] = "FromEnv"

    assert_equal "FromEnv", Fizzy::Oidc.config.account_name
  ensure
    ENV.delete("FIZZY_OIDC_ACCOUNT_NAME")
  end

  def test_group_boards_and_all_group_boards
    write_mapping(<<~YAML)
      mappings:
        default_boards: ["General"]
        admin_group: "admins"
        groups:
          eng:   { boards: ["Backend", "Infra"] }
          design: { boards: ["Design"] }
    YAML

    assert_equal ["General"], Fizzy::Oidc.config.default_boards
    assert_equal "admins", Fizzy::Oidc.config.admin_group
    assert_equal %w[Backend Infra], Fizzy::Oidc.config.group_boards(%w[eng])
    assert_equal %w[Backend Infra Design].sort, Fizzy::Oidc.config.all_group_boards.sort
    assert_equal [], Fizzy::Oidc.config.group_boards(%w[unknown])
  end

  def test_returns_empty_defaults_when_no_mapping_file
    assert_equal [], Fizzy::Oidc.config.default_boards
    assert_nil Fizzy::Oidc.config.admin_group
    assert_equal [], Fizzy::Oidc.config.all_group_boards
  end
end

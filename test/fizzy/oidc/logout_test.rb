require "test_helper"
require "minitest/mock"

class Fizzy::Oidc::LogoutTest < Minitest::Test
  ENDPOINT = "https://id.test/protocol/openid-connect/logout"

  def test_sends_the_id_token_and_the_way_back
    url = with_endpoint(ENDPOINT) { logout_url(id_token: "the.id.token") }

    assert_equal ENDPOINT, url.split("?").first
    assert_equal(
      { "client_id" => "client", "id_token_hint" => "the.id.token", "post_logout_redirect_uri" => "https://fizzy.test/session/new" },
      URI.decode_www_form(URI(url).query).to_h
    )
  end

  def test_names_the_client_when_the_session_kept_no_id_token
    url = with_endpoint(ENDPOINT) { logout_url(id_token: nil) }

    assert_equal(
      { "client_id" => "client", "post_logout_redirect_uri" => "https://fizzy.test/session/new" },
      URI.decode_www_form(URI(url).query).to_h
    )
  end

  def test_gives_up_when_the_idp_has_no_end_session_endpoint
    assert_nil with_endpoint(nil) { logout_url(id_token: "the.id.token") }
  end

  def test_gives_up_when_discovery_fails
    failing = ->(*) { raise OpenIDConnect::Discovery::DiscoveryFailed, "down" }

    OpenIDConnect::Discovery::Provider::Config.stub(:discover!, failing) do
      assert_nil logout_url(id_token: "the.id.token")
    end
  end

  private
    def logout_url(id_token:)
      Fizzy::Oidc::Logout.url(id_token:, post_logout_redirect_uri: "https://fizzy.test/session/new")
    end

    def with_endpoint(endpoint, &)
      discovered = OpenStruct.new(end_session_endpoint: endpoint)
      OpenIDConnect::Discovery::Provider::Config.stub(:discover!, discovered, &)
    end
end

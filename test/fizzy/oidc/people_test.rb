require "test_helper"

class Fizzy::Oidc::PeopleTest < Minitest::Test
  def setup
    super
    @account = Account.create!(name: "Acme")
    @me = person("Me")
    @general = board("General", @me)
    @infra = board("Infra", @me)
  end

  def test_people_sharing_a_board_are_the_members_of_my_boards_once_each
    alice = person("Alice", boards: [ @general, @infra ])
    bob = person("Bob", boards: [ @general ])
    person("Stranger", boards: [ board("Elsewhere", alice) ])
    person("Gone", boards: [ @general ], active: false)

    assert_equal [ alice, bob, @me ], Fizzy::Oidc::People.sharing_a_board_with(@me).alphabetically.to_a
  end

  def test_the_search_finds_non_members_by_name_or_email_regardless_of_case
    person("Alice Martin", boards: [ @general ])
    bob = person("Bob Martin", email: "bob@example.com")
    carol = person("Carol", email: "c.martin@example.com")
    person("Dan Martin", active: false)

    assert_equal [ bob, carol ], Fizzy::Oidc::People.addable_to(@general, " MARTIN ").to_a
    assert_equal [ bob ], Fizzy::Oidc::People.addable_to(@general, "Bob@Example").to_a
  end

  def test_the_search_ignores_accents_and_takes_like_wildcards_literally
    elodie = person("Élodie Dupont", email: "jean_dupont@example.com")
    person("Jean-Dupont", email: "jeanxdupont@example.com")
    percent = person("100% Remote", email: "remote@example.com")

    assert_equal [ elodie ], Fizzy::Oidc::People.addable_to(@general, "jean_dupont").to_a
    assert_equal [ elodie ], Fizzy::Oidc::People.addable_to(@general, "elodie").to_a
    assert_equal [ elodie ], Fizzy::Oidc::People.addable_to(@general, "ÉLODIE").to_a
    assert_equal [ percent ], Fizzy::Oidc::People.addable_to(@general, "%").to_a
  end

  def test_the_search_is_capped_and_needs_a_query
    25.times { |i| person("Member #{i}") }

    assert_equal Fizzy::Oidc::People::SEARCH_LIMIT, Fizzy::Oidc::People.addable_to(@general, "member").to_a.size
    assert_empty Fizzy::Oidc::People.addable_to(@general, " ").to_a
  end

  private
    def person(name, boards: [], email: "#{name.parameterize}@example.com", active: true)
      identity = Identity.create!(email_address: email)
      @account.users.create!(name:, identity:, active:).tap do |user|
        boards.each { |board| Access.create!(user:, board:, account: @account) }
      end
    end

    def board(name, creator)
      @account.boards.create!(name:, creator_id: creator.id).tap do |board|
        Access.create!(user: creator, board:, account: @account)
      end
    end
end

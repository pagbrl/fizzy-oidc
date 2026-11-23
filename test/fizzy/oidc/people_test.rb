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

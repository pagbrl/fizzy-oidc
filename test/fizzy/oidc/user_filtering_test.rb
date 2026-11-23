require "test_helper"
require "fizzy/oidc/patches/user_filtering"

class Fizzy::Oidc::UserFilteringTest < Minitest::Test
  Filter = Struct.new(:single_board, :assignees, :creators, :closers, keyword_init: true)

  class Filtering
    attr_reader :user, :filter

    def initialize(user, filter)
      @user, @filter = user, filter
    end

    prepend Fizzy::Oidc::Patches::UserFiltering

    private
      def account
        user.account
      end
  end

  def setup
    super
    @account = Account.create!(name: "Acme")
    @me = person("Me")
    @general = board("General", @me)
    @infra = board("Infra", @me)
    @alice = person("Alice", boards: [ @general ])
    @bob = person("Bob", boards: [ @infra ])
    @stranger = person("Stranger")
  end

  def test_a_board_page_lists_its_members
    filtering = Filtering.new(@me, filter)
    filtering.board = @infra

    assert_equal [ @bob, @me ], filtering.users.to_a
  end

  def test_a_filter_on_one_board_lists_its_members
    assert_equal [ @alice, @me ], Filtering.new(@me, filter(single_board: @general)).users.to_a
  end

  def test_a_cross_board_page_lists_the_people_sharing_a_board
    assert_equal [ @alice, @bob, @me ], Filtering.new(@me, filter).users.to_a
  end

  def test_people_already_picked_stay_listed
    filtering = Filtering.new(@me, filter(single_board: @general, assignees: [ @stranger ], closers: [ @bob ]))

    assert_equal [ @alice, @bob, @me, @stranger ], filtering.users.to_a
  end

  private
    def filter(single_board: nil, assignees: [], creators: [], closers: [])
      Filter.new(single_board:, assignees:, creators:, closers:)
    end

    def person(name, boards: [])
      identity = Identity.create!(email_address: "#{name.downcase}@example.com")
      @account.users.create!(name:, identity:).tap do |user|
        boards.each { |board| Access.create!(user:, board:, account: @account) }
      end
    end

    def board(name, creator)
      @account.boards.create!(name:, creator_id: creator.id).tap do |board|
        Access.create!(user: creator, board:, account: @account)
      end
    end
end

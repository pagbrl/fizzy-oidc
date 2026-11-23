require "test_helper"
require "fizzy/oidc/patches/user_filtering"

class Fizzy::Oidc::UserFilteringTest < Minitest::Test
  Filter = Struct.new(:single_board, :boards, :assignees, :creators, :closers, keyword_init: true)

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
    @alice, @bob, @carol, @stranger = %w[ Alice Bob Carol Stranger ].map { person(it, boards: [ @general, @infra ]) }

    general_card = Card.create!(board: @general, creator: @alice)
    Assignment.create!(card: general_card, assignee: @bob)
    infra_card = Card.create!(board: @infra, creator: @me)
    Assignment.create!(card: infra_card, assignee: @carol)
    Closure.create!(card: infra_card, user: @alice)
    elsewhere = board("Elsewhere", @stranger)
    Card.create!(board: elsewhere, creator: @stranger)

    Event.create!(board: @infra, creator: @carol, action: "comment_created")
    Event.create!(board: @general, creator: @bob, action: "card_published")
    Event.create!(board: @general, creator: @alice, action: "card_assigned")
    Event.create!(board: elsewhere, creator: @stranger, action: "comment_created")
  end

  def test_the_activity_person_filter_offers_the_authors_of_timeline_events
    assert_equal [ @bob, @carol ], Filtering.new(@me, filter).author_choices.to_a
    assert_equal [ @bob, @stranger ], Filtering.new(@me, filter(single_board: @general, creators: [ @stranger ])).author_choices.to_a
  end

  def test_a_filter_on_several_boards_looks_at_those_boards_only
    filtering = Filtering.new(@me, filter(boards: Board.where(id: @infra.id)))

    assert_equal [ @carol ], filtering.assignee_choices.to_a
    assert_equal [ @carol ], filtering.author_choices.to_a
  end

  def test_each_filter_offers_who_holds_its_role_on_my_boards
    filtering = Filtering.new(@me, filter)

    assert_equal [ @bob, @carol ], filtering.assignee_choices.to_a
    assert_equal [ @alice, @me ], filtering.creator_choices.to_a
    assert_equal [ @alice ], filtering.closer_choices.to_a
  end

  def test_a_board_page_offers_the_people_on_its_cards
    filtering = Filtering.new(@me, filter)
    filtering.board = @infra

    assert_equal [ @carol ], filtering.assignee_choices.to_a
    assert_equal [ @me ], filtering.creator_choices.to_a
  end

  def test_a_filter_on_one_board_offers_the_people_on_its_cards
    filtering = Filtering.new(@me, filter(single_board: @general))

    assert_equal [ @bob ], filtering.assignee_choices.to_a
    assert_equal [], filtering.closer_choices.to_a
  end

  def test_people_already_picked_stay_listed
    filtering = Filtering.new(@me, filter(single_board: @general, assignees: [ @stranger ], closers: [ @bob ]))

    assert_equal [ @bob, @stranger ], filtering.assignee_choices.to_a
    assert_equal [ @bob ], filtering.closer_choices.to_a
  end

  private
    def filter(single_board: nil, boards: Board.none, assignees: [], creators: [], closers: [])
      Filter.new(single_board:, boards:, assignees:, creators:, closers:)
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

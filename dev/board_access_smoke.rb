# Round trip through the overridden boards/edit/_users partial and the real
# BoardsController#update: a member the page fails to render checked is a
# member the next save revokes. Run inside a Fizzy that loads the gem:
#
#   bin/rails runner /path/to/dev/board_access_smoke.rb
#
# It creates a board and four people, then deletes them.
require "action_dispatch/testing/integration"
require "action_dispatch/testing/test_request"

def check(label, expected, actual)
  raise "#{label}: expected #{expected.sort.inspect}, got #{actual.sort.inspect}" unless expected.sort == actual.sort
  puts "ok  #{label}"
end

def board_form(html)
  Nokogiri::HTML(html).css("form").find { |form| form.at_css('input[name="_method"][value="patch"]') && form.at_css('input[name="user_ids[]"]') } or raise "no board form on the page"
end

def fields(form, extra = {})
  pairs = form.css("input[name]").reject { |input| %w[ checkbox radio ].include?(input["type"]) && !input["checked"] }
  URI.encode_www_form(pairs.map { |input| [ input["name"], input["value"].to_s ] } + extra.to_a)
end

def ticked(form)
  form.css('input[name="user_ids[]"][checked]').map { it["value"] }
end

stamp = SecureRandom.hex(3)
account = Account.joins(:users).merge(User.where(role: :owner, active: true)).first or raise "no account with an active owner"
owner = account.users.find_by!(role: :owner, active: true)
people = %w[ Kept Kept Searched Searched ].each_with_index.map do |label, i|
  identity = Identity.create!(email_address: "board-access-smoke-#{stamp}-#{i}@example.invalid")
  account.users.create!(name: "Smoke #{label} #{stamp} #{i}", identity:, role: :member)
end
kept, searched = people.first(2), people.last(2)
board = Current.set(account:, user: owner) { account.boards.create!(name: "Board access smoke #{stamp}", creator: owner, all_access: false) }
board.accesses.grant_to kept

begin
  session = owner.identity.sessions.create!
  jar = ActionDispatch::TestRequest.create.cookie_jar
  jar.signed[:session_token] = session.signed_id

  app = ActionDispatch::Integration::Session.new(Rails.application)
  app.host! "localhost"
  app.cookies["session_token"] = jar[:session_token]
  edit_path = "#{account.slug}/boards/#{board.id}/edit"
  board_path = "#{account.slug}/boards/#{board.id}"
  form_post = { "Content-Type" => "application/x-www-form-urlencoded" }
  frame = form_post.merge("Turbo-Frame" => "board_access_search_results")

  app.get edit_path
  raise "GET edit: #{app.response.status}" unless app.response.ok?
  form = board_form(app.response.body)
  members = board.users.active.ids
  check "every member is rendered checked", members, ticked(form)

  app.post board_path, params: fields(form, "q" => searched[0].name, "search_people" => "1"), headers: frame
  raise "first search: #{app.response.status}" unless app.response.ok?
  found = board_form(app.response.body).css('input[name="user_ids[]"]:not([checked])').map { it["value"] }
  check "the first search finds the first outsider", [ searched[0].id ], found - members

  app.post board_path, params: fields(form, "q" => searched[1].name, "search_people" => "1", "user_ids[]" => searched[0].id), headers: frame
  raise "second search: #{app.response.status}" unless app.response.ok?
  form = board_form(app.response.body)
  check "the second search keeps the first outsider ticked", members + [ searched[0].id ], ticked(form)

  app.post board_path, params: fields(form, "user_ids[]" => searched[1].id), headers: form_post
  raise "save: #{app.response.status}" unless app.response.redirect?
  check "after the save, members are kept and both outsiders granted", [ owner.id, *people.map(&:id) ], board.reload.users.ids
ensure
  Rails.application.executor.wrap do
    board.destroy!
    people.each { |person| person.destroy!; person.identity.destroy! }
    session&.destroy!
  end
end

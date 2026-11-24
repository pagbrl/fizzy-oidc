# Round trip through the overridden boards/edit/_users partial and the real
# BoardsController#update: a member the page fails to render checked is a
# member the next save revokes. Then a project group: attached, its member
# locked on and kept by a save, detached. Run inside a Fizzy that loads the gem:
#
#   bin/rails runner /path/to/dev/board_access_smoke.rb
#
# It creates a board, five people and a group, then deletes them.
require "action_dispatch/testing/integration"
require "action_dispatch/testing/test_request"

def check(label, expected, actual)
  raise "#{label}: expected #{expected.sort.inspect}, got #{actual.sort.inspect}" unless expected.sort == actual.sort
  puts "ok  #{label}"
end

def board_form(html)
  Nokogiri::HTML(html).css("form").find { |form| form.at_css('input[name="_method"][value="patch"]') && form.at_css('input[name="user_ids[]"]') } or raise "no board form on the page"
end

# What a browser submits: no unticked boxes, nothing disabled.
def fields(form, extra = {})
  pairs = form.css("input[name]").reject { |input| input["disabled"] || (%w[ checkbox radio ].include?(input["type"]) && !input["checked"]) }
  URI.encode_www_form(pairs.map { |input| [ input["name"], input["value"].to_s ] } + extra.to_a)
end

def ticked(form)
  form.css('input[name="user_ids[]"][checked]').map { it["value"] }
end

stamp = SecureRandom.hex(3)
account = Account.joins(:users).merge(User.where(role: :owner, active: true)).first or raise "no account with an active owner"
owner = account.users.find_by!(role: :owner, active: true)
people = %w[ Kept Kept Searched Searched Grouped ].each_with_index.map do |label, i|
  identity = Identity.create!(email_address: "board-access-smoke-#{stamp}-#{i}@example.invalid")
  account.users.create!(name: "Smoke #{label} #{stamp} #{i}", identity:, role: :member)
end
kept, searched, grouped = people[0, 2], people[2, 2], people[4]
group_name = "Projet Smoke #{stamp}"
Fizzy::Oidc::ProjectGroups.sync_member(grouped, [ "/#{group_name}" ])
group = Fizzy::Oidc::Group.find_by!(account:, name: group_name)
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
  # Fizzy refuses a form post without the header a browser sends (production
  # forgery protection by Sec-Fetch-Site).
  form_post = { "Content-Type" => "application/x-www-form-urlencoded", "Sec-Fetch-Site" => "same-origin" }
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
  check "after the save, members are kept and both outsiders granted", [ owner.id, *kept.map(&:id), *searched.map(&:id) ], board.reload.users.ids
  members = board.users.ids

  app.get edit_path
  form = board_form(app.response.body)
  app.post board_path, params: fields(form, "group_q" => stamp, "search_groups" => "1"), headers: form_post.merge("Turbo-Frame" => "board_group_search_results")
  raise "group search: #{app.response.status}" unless app.response.ok?
  found = board_form(app.response.body).css('input[name="group_ids[]"]:not([checked])').map { it["value"] }
  check "the group search finds the group", [ group.id ], found - [ "" ]

  app.post board_path, params: fields(form, "group_ids[]" => group.id), headers: form_post
  raise "save with the group: #{app.response.status}" unless app.response.redirect?
  check "attaching the group lets its member in", members + [ grouped.id ], board.reload.users.ids
  check "the group's access is recorded as such", [ grouped.id ], Fizzy::Oidc::GroupGrant.where(board_id: board.id).pluck(:user_id)

  app.get edit_path
  form = board_form(app.response.body)
  locked = form.css('input[name="user_ids[]"][disabled]').map { it["value"] }
  check "the group's member is rendered locked", [ grouped.id ], locked
  raise "no via mention" unless app.response.body.include?("via #{group_name}")
  check "the group is rendered ticked", [ group.id ], form.css('input[name="group_ids[]"][checked]').map { it["value"] }

  app.post board_path, params: fields(form), headers: form_post
  check "a save without the locked member keeps them", members + [ grouped.id ], board.reload.users.ids

  app.get edit_path
  form = board_form(app.response.body)
  form.css('input[name="group_ids[]"][checked]').each { it.remove_attribute("checked") }
  app.post board_path, params: fields(form), headers: form_post
  check "unticking the group takes back only its access", members, board.reload.users.ids
ensure
  Rails.application.executor.wrap do
    group&.destroy!
    board.destroy!
    people.each { |person| person.destroy!; person.identity.destroy! }
    session&.destroy!
  end
end

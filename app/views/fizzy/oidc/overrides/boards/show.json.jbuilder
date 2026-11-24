json.partial! "boards/board", board: @board
unless @board.all_access?
  json.user_ids @board.users.ids
  json.group_user_ids Fizzy::Oidc::ProjectGroups.group_user_ids(@board)
end

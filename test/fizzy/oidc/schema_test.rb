require "test_helper"

class Fizzy::Oidc::SchemaTest < Minitest::Test
  def test_adds_the_columns_a_schema_load_skipped
    connection = ActiveRecord::Base.connection
    connection.remove_index :identities, [:oidc_provider, :oidc_subject]
    connection.remove_column :identities, :oidc_subject
    connection.remove_column :identities, :oidc_provider

    Fizzy::Oidc::Schema.ensure!
    Fizzy::Oidc::Schema.ensure!

    assert connection.column_exists?(:identities, :oidc_subject)
    assert connection.column_exists?(:identities, :oidc_provider)
    assert connection.index_exists?(:identities, [:oidc_provider, :oidc_subject], unique: true)
  ensure
    Identity.reset_column_information
  end
end

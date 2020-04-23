Sequel.migration do
  change do
    alter_table(:entry) do
      set_column_not_null :feed
      set_column_not_null :url
      set_column_not_null :published
    end
  end
end

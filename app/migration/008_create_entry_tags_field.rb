Sequel.migration do
  change do
    alter_table(:entry) do
      add_column :extra_tags, 'text'
    end
  end
end

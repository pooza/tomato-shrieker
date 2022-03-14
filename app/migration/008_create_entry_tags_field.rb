Sequel.migration do
  change do
    alter_table(:entry) do
      add_column :tags
    end
  end
end

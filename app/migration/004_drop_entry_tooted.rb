Sequel.migration do
  change do
    alter_table(:entry) do
      drop_column :tooted
    end
  end
end

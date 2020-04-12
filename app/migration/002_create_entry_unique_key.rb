Sequel.migration do
  change do
    alter_table(:entry) do
      add_index [:feed, :title, :summary, :url, :enclosure_url], unique: true
    end
  end
end

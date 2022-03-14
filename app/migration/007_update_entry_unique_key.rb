Sequel.migration do
  change do
    alter_table(:entry) do
      drop_index :feed, {name: :entry_feed_url_published_index}
      add_index [:feed, :title, :url], {unique: true}
    end
  end
end

Sequel.migration do
  change do
    create_table :entry do
      primary_key :id
      text :feed
      text :title
      text :summary
      text :url
      text :enclosure_url
      timestamp :published
      timestamp :tooted
    end
  end
end

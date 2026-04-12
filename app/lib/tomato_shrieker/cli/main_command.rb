# frozen_string_literal: true

module TomatoShrieker
  class MainCommand < Thor
    desc 'source SUBCOMMAND', 'ソース管理'
    subcommand 'source', SourceCommand
  end
end

# frozen_string_literal: true

module TomatoShrieker
  class MainCommand < Thor
    def self.exit_on_failure?
      return true
    end

    desc 'source SUBCOMMAND', 'ソース管理'
    subcommand 'source', SourceCommand
  end
end

module TomatoShrieker
  class Environment < Ginseng::Environment
    include Package

    def self.name
      return File.basename(dir)
    end

    def self.dir
      return TomatoShrieker.dir
    end

    def self.dsn
      return "sqlite://#{db}"
    end

    def self.rake?
      return ENV['RAKE'].present? && !test? rescue false
    end

    def self.test?
      return ENV['TEST'].present? rescue false
    end

    def self.type
      return config['/environment'] || 'development'
    end

    def self.development?
      return type == 'development'
    end

    def self.production?
      return type == 'production'
    end

    def self.db
      return File.join(
        dir,
        'tmp/db',
        config['/sqlite3/db'],
      )
    end

    def self.setup_database
      return if Sequel::Model.db
      Sequel::Model.db = Sequel.connect(dsn)
    end
  end
end

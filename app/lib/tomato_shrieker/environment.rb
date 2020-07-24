module TomatoShrieker
  class Environment < Ginseng::Environment
    def self.name
      return File.basename(dir)
    end

    def self.dir
      return TomatoShrieker.dir
    end

    def self.dsn
      return "sqlite://#{db}"
    end

    def self.db
      return File.join(
        dir,
        'tmp/db',
        Config.instance['/sqlite3/db'],
      )
    end
  end
end

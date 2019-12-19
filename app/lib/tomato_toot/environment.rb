module TomatoToot
  class Environment < Ginseng::Environment
    def self.name
      return File.basename(dir)
    end

    def self.dir
      return TomatoToot.dir
    end
  end
end

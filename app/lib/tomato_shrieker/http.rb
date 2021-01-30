module TomatoShrieker
  class HTTP < Ginseng::HTTP
    include Package

    def self.config
      return Config.instance
    end
  end
end

module TomatoShrieker
  class Template < Ginseng::Template
    include Package
    attr_reader :path

    def initialize(name)
      @path = name if name.start_with?('/') && File.exist?(name)
      @path ||= File.join(environment_class.dir, dir, "#{name.sub(/\.erb$/, '')}.erb")
      super(@path)
    end

    def source
      return params[:source] || params[:feed]
    end

    alias feed source

    def entry
      return params[:entry]
    end
  end
end

module TomatoShrieker
  class Template < Ginseng::Template
    include Package

    def source
      return params[:source] || params[:feed]
    end

    alias feed source

    def entry
      return params[:entry]
    end
  end
end

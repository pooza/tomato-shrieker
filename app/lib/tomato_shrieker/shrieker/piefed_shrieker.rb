module TomatoShrieker
  class PiefedShrieker < Ginseng::Piefed::Service
    def initialize(params = {})
      params = params.deep_symbolize_keys
      params[:url] = "https://#{params[:host]}" if params[:host] && !params[:url]
      params[:user] = params[:user_id] if params[:user_id] && !params[:user]
      super
      login
    end

    def api_version
      return @params[:api_version] || super
    end

    def exec(body)
      template = create_piefed_template(body[:template])
      data = {
        title: template.to_s.gsub(/[\r\n[:blank:]]+/, ' '),
        body: template.to_s,
        community_id: template.source['/dest/piefed/community_id'],
      }
      Ginseng::URI.scan(data[:body]).each {|uri| data[:body].gsub!(uri.to_s, '')}
      data[:title].ellipsize!(TomatoShrieker::Config.instance['/piefed/subject/max_length'])
      uri = (template.entry || template.source).uri rescue Ginseng::URI.scan(template.to_s).first
      data[:url] = uri.to_s if uri
      return http.post("/api/#{api_version}/post", {
        body: data,
        headers: {'Authorization' => "Bearer #{@jwt}"},
      })
    end

    private

    def create_piefed_template(original)
      source = original.source
      piefed_template_name = source['/dest/piefed/template']
      return original unless piefed_template_name

      template = Template.new(piefed_template_name)
      template[:source] = source
      template[:entry] = original.entry
      template[:status] = original[:status]
      return template
    end
  end
end

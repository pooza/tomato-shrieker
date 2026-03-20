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
      template = search_template(body)
      data = {
        title: template.to_s.gsub(/[\r\n[:blank:]]+/, ' '),
        body: template.to_s,
        community_id: template.source['/dest/piefed/community_id'],
      }
      Ginseng::URI.scan(data[:body]).each {|uri| data[:body].gsub!(uri.to_s, '')}
      data[:title].ellipsize!(config['/piefed/subject/max_length'])
      uri = (template.entry || template.source).uri rescue Ginseng::URI.scan(template.to_s).first
      data[:url] = uri.to_s if uri
      return http.post("/api/#{api_version}/post", {
        body: data,
        headers: {'Authorization' => "Bearer #{@jwt}"},
      })
    end

    private

    def search_template(body)
      unless entry = body[:template].entry
        return body[:template].source.create_template(:piefed, body[:template].to_s)
      end
      return entry.create_template(:piefed)
    rescue
      return body[:template]
    end
  end
end

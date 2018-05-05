Plugin.create(:twitter_card) do
  module Plugin::TwitterCard
    class TwitterCardMeta < Diva::Model
      include Diva::Model::UserMixin
      register :twitter_card_meta, name: "Twitter Card: Title & Icon"

      field.string :title, required: true
      field.uri :favicon

      alias_method :name, :title

      def icon
        photo = Plugin.filtering(:photo_filter, favicon, [])[1].first
        if photo.nil?
          photo = Skin['notfound.png']
        end
        photo
      end
    end

    class TwitterCard < Diva::Model
      include Diva::Model::MessageMixin

      register :twitter_card, name: "Twitter Card", timeline: true

      field.uri :uri, required: true
      field.has :meta, TwitterCardMeta, required: true
      field.string :description, required: true
      field.time :created

      alias_method :perma_link, :uri
      alias_method :user, :meta # Gdk::SubPartsMessageBase#header_left_contentが要求するので良くわからないが置く

      handle %r|\Ahttps?://| do |uri|
        TwitterCard.from_cache(uri) || Thread.new { TwitterCard.fetch(uri) }
      end

      @@cache = WeakStorage.new(String, TwitterCard)

      def self.fetch(uri)
        client = HTTPClient.new
        resp = client.get uri, follow_redirect: true
        return nil if resp.status != 200

        headers = resp.http_header.all.to_h
        created = nil
        if headers['Date']
          created = Time.parse(headers["Date"])
        end
        page = resp.content
        doc = Nokogiri::HTML(page)
        metas = doc.css('head > meta')

        props = metas.map {|meta|
          name = meta.attribute('name') || meta.attribute('property')
          content = meta.attribute('content')
          [name, content]
        }.select{|name, content|
          name && content && (name.to_s.start_with?('og:') || name.to_s.start_with?('twitter:'))
        }.map{|pair|
          pair.map(&:to_s)
        }.to_h

        title = props['twitter:title'] || props['og:title']
        return nil unless title
        description = props['twitter:description'] || props['og:description']
        description = description.gsub(/[\r\n]/){ ' ' }[0...200]
        favicon = props['twitter:image'] || props['og:image']

        TwitterCard.new(
          uri: uri,
          description: description,
          created: created,
          meta: {
            title: title,
            favicon: favicon,
          }
        )
      end

      def self.from_cache(uri)
        @@cache[uri.to_s]
      end

      def icon
        meta.icon
      end

      def around
        [self]
      end

      def source
        'OpenGraph'
      end
    end
  end
end

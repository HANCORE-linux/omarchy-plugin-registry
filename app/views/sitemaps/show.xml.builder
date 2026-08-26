xml.instruct!
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  [ "", "/governance", "/publishing", "/audit" ].each do |path|
    xml.url do
      xml.loc "#{@base}#{path}"
    end
  end
  @publishers.each do |publisher|
    xml.url do
      xml.loc "#{@base}/publishers/#{publisher.name}"
    end
  end
  @plugins.each do |plugin|
    xml.url do
      xml.loc "#{@base}/plugins/#{plugin.publisher.name}/#{plugin.name}"
      xml.lastmod plugin.updated_at.utc.iso8601
    end
  end
end

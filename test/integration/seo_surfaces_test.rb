require "test_helper"

# OG cards, social meta, sitemap, and the Atom feed.
class SeoSurfacesTest < ActionDispatch::IntegrationTest
  setup do
    @publisher = Publisher.create!(name: "acme", kind: :org)
    @plugin = Plugin.create!(publisher: @publisher, name: "weather", summary: "Forecast in the bar",
      latest_version: "1.0.0", category: "widgets", downloads_count: 10)
    @plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: "0" * 64, size_bytes: 1,
      state: :published, published_at: 2.days.ago)
  end

  test "plugin og card renders a 1200x630 png" do
    get "/og/acme/weather.png"
    assert_response :success
    assert_equal "image/png", response.media_type
    image = Vips::Image.new_from_buffer(response.body, "")
    assert_equal [ 1200, 630 ], [ image.width, image.height ]
  end

  test "site og card renders and is referenced from the home page" do
    get "/og/site.png"
    assert_response :success
    assert_equal "image/png", response.media_type

    get "/"
    assert_select "meta[property='og:image'][content=?]", "http://registry.test/og/site.png"
    assert_select "meta[name='twitter:card'][content='summary_large_image']"
  end

  test "plugin pages carry their own social meta" do
    get "/plugins/acme/weather"
    assert_select "meta[property='og:title'][content='acme/weather']"
    assert_select "meta[property='og:description'][content='Forecast in the bar']"
    assert_select "meta[property='og:image'][content=?]", "http://registry.test/og/acme/weather.png"
    assert_select "meta[name='description'][content='Forecast in the bar']"
  end

  test "sitemap lists static pages, publishers, and plugins" do
    get "/sitemap.xml"
    assert_response :success
    assert_match "<loc>http://registry.test/plugins/acme/weather</loc>", response.body
    assert_match "<loc>http://registry.test/publishers/acme</loc>", response.body
    assert_match "<loc>http://registry.test/governance</loc>", response.body
  end

  test "atom feed lists recent releases" do
    get "/feed.xml"
    assert_response :success
    assert_match "acme/weather v1.0.0", response.body
    assert_match "<link rel=\"alternate\" href=\"http://registry.test/plugins/acme/weather\"/>", response.body
  end
end

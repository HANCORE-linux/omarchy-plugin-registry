require "test_helper"
require "vips"

class PreviewImageTest < ActiveSupport::TestCase
  def png(width: 640, height: 360)
    Vips::Image.black(width, height).add(40).cast("uchar").pngsave_buffer
  end

  def animated_gif(frames: 3, width: 320, height: 180)
    strip = Vips::Image.arrayjoin(frames.times.map { |i| Vips::Image.black(width, height).add(i * 50).cast("uchar") }, across: 1).copy
    strip.set_type(GObject::GINT_TYPE, "page-height", height)
    strip.set_type(GObject::GINT_TYPE, "n-pages", frames)
    strip.gifsave_buffer
  end

  test "processes a static png into card and detail webp renditions" do
    result = Registry::PreviewImage.process(png(width: 1920, height: 1080), name: "preview.png")

    assert_equal 720, result[:meta]["card"]["width"]
    assert_equal 405, result[:meta]["card"]["height"]
    assert_equal 1600, result[:meta]["detail"]["width"]
    assert_not result[:meta]["animated"]
    assert_equal "webpload_buffer", Vips::Image.new_from_buffer(result[:card], "").get("vips-loader")
  end

  test "never upscales a small preview" do
    result = Registry::PreviewImage.process(png(width: 320, height: 200), name: "preview.png")
    assert_equal 320, result[:meta]["card"]["width"]
    assert_equal 320, result[:meta]["detail"]["width"]
  end

  test "keeps gif animation in the detail rendition and freezes the card" do
    result = Registry::PreviewImage.process(animated_gif, name: "preview.gif")

    assert result[:meta]["animated"]
    detail = Vips::Image.new_from_buffer(result[:detail], "", n: -1)
    assert_equal 3, detail.get("n-pages")
    card = Vips::Image.new_from_buffer(result[:card], "")
    assert card.get_typeof("n-pages").zero? || card.get("n-pages") == 1
  end

  test "rejects bytes that do not match the extension" do
    error = assert_raises(Registry::PreviewImage::InvalidPreview) do
      Registry::PreviewImage.validate!(png, name: "preview.gif")
    end
    assert_match(/does not contain GIF data/, error.message)
  end

  test "rejects undecodable bytes and oversized stills" do
    assert_raises(Registry::PreviewImage::InvalidPreview) do
      Registry::PreviewImage.validate!("GIF89a-but-not-really", name: "preview.gif")
    end
    assert_raises(Registry::PreviewImage::InvalidPreview) do
      Registry::PreviewImage.validate!(png(width: 9000, height: 5000), name: "preview.png")
    end
  end

  test "rejects animations with oversized frames" do
    error = assert_raises(Registry::PreviewImage::InvalidPreview) do
      Registry::PreviewImage.validate!(animated_gif(frames: 2, width: 2600, height: 1600), name: "preview.gif")
    end
    assert_match(/animated preview frames exceed/, error.message)
  end
end

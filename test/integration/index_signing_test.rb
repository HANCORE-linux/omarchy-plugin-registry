require "test_helper"

class IndexSigningTest < ActionDispatch::IntegrationTest
  setup do
    @dev = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @dev, role: :owner, founding: true)
    perform_enqueued_jobs do
      Registry::PublishVersion.new(user: @dev, publisher: @publisher, plugin_name: "weather",
        tarball_bytes: TarballBuilder.build).call
    end
  end

  test "every index file carries a verifiable detached signature" do
    %w[config.json all.json revocations.json index/acme/weather.json].each do |file|
      content = DataPlane.read(file)
      signature = DataPlane.read("#{file}.sig")
      assert DataPlane::Signer.verify?(content, signature), "bad signature for #{file}"
    end
  end

  test "signatures and public key are served over HTTP" do
    get "/signing-key.pub"
    assert_response :success
    key = response.body

    get "/revocations.json"
    content = response.body
    get "/revocations.json", params: { sig: 1 }
    signature = response.body

    verify_key = Ed25519::VerifyKey.new(Base64.strict_decode64(key))
    assert verify_key.verify(Base64.strict_decode64(signature), content)
  end

  test "a tampered index fails verification" do
    content = DataPlane.read("all.json")
    signature = DataPlane.read("all.json.sig")
    assert_not DataPlane::Signer.verify?(content + " ", signature)
  end

  test "signed files carry strictly increasing millisecond-anchored generations with expiry" do
    first = JSON.parse(DataPlane.read("revocations.json"))
    assert_kind_of Integer, first["generation"]
    assert_operator first["generation"], :>=, (Time.current.to_f * 1000).to_i - 60_000
    assert Time.parse(first["expires_at"]).future?

    DataPlane::Regenerate.all
    second = JSON.parse(DataPlane.read("revocations.json"))
    assert_operator second["generation"], :>, first["generation"]

    # every signed file of one run carries the same generation; the index meta
    # line carries it too
    config = JSON.parse(DataPlane.read("config.json"))
    all = JSON.parse(DataPlane.read("all.json"))
    meta = JSON.parse(DataPlane.read("index/acme/weather.json").lines.first)
    assert meta["meta"]
    assert_equal second["generation"], config["generation"]
    assert_equal second["generation"], all["generation"]
    assert_equal second["generation"], meta["generation"]
    assert Time.parse(meta["expires_at"]).future?
  end

  test "a changed signing key refuses to replace the trust root" do
    original_pub = DataPlane.root.join("signing-key.pub").read
    DataPlane.root.join("signing-key.pub").write("SOMEONE-ELSES-KEY")
    error = assert_raises(RuntimeError) { DataPlane::Regenerate.all }
    assert_match(/refusing to replace the trust root/, error.message)
  ensure
    DataPlane.root.join("signing-key.pub").write(original_pub)
  end
end

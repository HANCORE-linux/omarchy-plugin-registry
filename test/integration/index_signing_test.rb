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
end

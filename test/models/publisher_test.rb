require "test_helper"

class PublisherTest < ActiveSupport::TestCase
  test "claims a valid name" do
    assert Publisher.new(name: "acme", kind: :org).valid?
  end

  test "rejects reserved names and the omarchy prefix" do
    assert_not Publisher.new(name: "admin", kind: :org).valid?
    assert_not Publisher.new(name: "omarchy", kind: :org).valid?
    assert_not Publisher.new(name: "omarchy-widgets", kind: :org).valid?
  end

  test "rejects uppercase and leading separators" do
    assert_not Publisher.new(name: "Acme", kind: :org).valid?
    assert_not Publisher.new(name: "-acme", kind: :org).valid?
  end

  test "rejects confusable lookalikes of existing publishers" do
    Publisher.create!(name: "acme", kind: :org)
    assert_not Publisher.new(name: "a-cme", kind: :org).valid?
    assert_not Publisher.new(name: "acm.e", kind: :org).valid?
  end
end

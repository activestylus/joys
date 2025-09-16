require_relative 'test_helper'

class JoysComponentTest < Minitest::Test
  def setup
    Joys.reset!
  end

  def test_component_without_block
    Joys.define(:comp, :badge) do |text|
      span(class: "badge") { txt(text) }
    end

    actual   = Joys.comp(:badge, "New!")
    expected = %(<span class="badge">New!</span>)

    assert_equal expected, actual
  end

def test_component_with_block
Joys.define(:comp, :card) do |title, block = nil|
  div(class: "card") {
    h3 { txt(title) }
    div(class: "card-body") {
      instance_eval(&block) if block
    }
  }
end

  actual = Joys.comp(:card, "Greetings") do
    p { txt("Hello world") }
    p { txt("This is inside the card.") }
  end

  expected = <<~HTML.strip
    <div class="card">
      <h3>Greetings</h3>
      <div class="card-body">
        <p>Hello world</p>
        <p>This is inside the card.</p>
      </div>
    </div>
  HTML

  assert_equal expected.gsub(/\s+/, ""), actual.gsub(/\s+/, "")
end

end

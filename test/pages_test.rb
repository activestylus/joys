require_relative 'test_helper'

class JoysPageTest < Minitest::Test
  def setup
    # Reset Joys state before each test to avoid bleed-over
    Joys.reset!
  end

def normalize_html(html)
  html
    .downcase
    .gsub(/\s+/, " ")        # collapse whitespace
    .gsub(/>\s+</, "><")     # remove spaces between tags
    .gsub(/^\s+|\s+$/, "")   # strip leading/trailing spaces
    .gsub(/>\s+/, ">")       # remove spaces after '>'
    .gsub(/\s+</, "<")       # remove spaces before '<'
end


  def test_layout_and_page_with_push_pull
    Joys.define(:layout, :main) do
      doctype
      html(lang: "en") {
        head { title { pull(:title) } }
        body { pull(:main) }
        footer { pull(:footer) }
      }
    end

    Joys.define(:page, :home) do
      layout(:main) {
        push(:title)  { txt("Hello World") }
        push(:main)   { txt("This is the body") }
        push(:footer) {
          txt("© 2024 Joys Framework. Built with ❤️ and nuclear-powered components.")
        }
      }
    end

    expected = <<~HTML.strip
      <!DOCTYPE html>
      <html lang="en">
        <head>
          <title>Hello World</title>
        </head>
        <body>This is the body</body>
        <footer>© 2024 Joys Framework. Built with ❤️ and nuclear-powered components.</footer>
      </html>
    HTML

    actual = Joys.page(:home)

    assert_equal normalize_html(expected), normalize_html(actual)
  end
end

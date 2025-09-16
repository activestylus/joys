require_relative 'test_helper'

class ModularPageTest < Minitest::Test
  def setup
    Joys.clear_cache!
  end
  
  def test_modular_page_architecture
    # Define simple layout first
    Joys.define(:layout, :simple) do
      html { body { pull(:main) } }
    end

    # Test data
    test_data = {
      hero: { title: "Test Product", cta: "Sign Up" },
      features: { 
        items: [
          { title: "Fast", desc: "Super quick" },
          { title: "Easy", desc: "Simple to use" }
        ]
      }
    }

    # Create the modular page module
    test_module = Module.new do
      define_singleton_method(:render) do |data|
        # Pre-render sections
        hero_html = hero(data[:hero])
        features_html = features(data[:features])
        
        # Define the page with pre-rendered content
        Joys.define(:page, :test_product) do
          layout(:simple) {
            push(:main) {
              raw hero_html
              raw features_html
            }
          }
        end
        
        # Render and return the page
        Joys.page(:test_product)
      end

      define_singleton_method(:hero) do |data|
        Joys.html {
          section(cs: "hero") {
            h1(data[:title])
            a(data[:cta], href: "/signup")
          }
        }
      end

      define_singleton_method(:features) do |data|
        Joys.html {
          section(cs: "features") {
            data[:items].each { |item|
              div {
                h3(item[:title])
                p(item[:desc])
              }
            }
          }
        }
      end
    end
    
    # Render the modular page
    html = test_module.render(test_data)
    
    # Assertions
    assert_includes html, "<h1>Test Product</h1>"
    assert_includes html, '<a href="/signup">Sign Up</a>'
    assert_includes html, "<h3>Fast</h3>"
    assert_includes html, "<p>Super quick</p>"
  end
end
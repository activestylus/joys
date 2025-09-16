require_relative 'test_helper'

class JoysTagsTest < Minitest::Test
  def setup
    @renderer = Object.new
    @renderer.extend(Joys::Render::Helpers)
    @renderer.extend(Joys::Tags)
    reset_buffer!
  end
  
  def teardown
    @renderer = nil
  end
  
  def reset_buffer!
    @renderer.instance_eval { @bf = String.new; @slots = {} }
  end
  
  def render(&block)
    reset_buffer!  # Always start fresh
    @renderer.instance_eval(&block)
    @renderer.instance_variable_get(:@bf)
  end
  
  # 🎯 Regular Tag Tests
  
  def test_simple_tag_renders_content
    html = render { div("Hello World") }
    assert_equal "<div>Hello World</div>", html
  end
  
  def test_xss_protection_escapes_evil_scripts
    malicious = "<script>alert('pwned')</script>"
    html = render { div(malicious) }
    assert_equal "<div>&lt;script&gt;alert(&#39;pwned&#39;)&lt;/script&gt;</div>", html
    refute_includes html, "<script>"  # Double-check no actual script tags
  end
  
  def test_class_string_adds_single_class
    html = render { div("Styled", cs: "fancy-card") }
    assert_equal '<div class="fancy-card">Styled</div>', html
  end
  
  def test_class_array_joins_multiple_classes
    html = render { div("Multi", cs: ["card", "primary", "shadow-xl"]) }
    assert_equal '<div class="card primary shadow-xl">Multi</div>', html
  end
  
  def test_class_array_filters_nil_and_false
    user_active = false
    html = render { 
      div("Smart", cs: ["base", nil, user_active && "active", "final"]) 
    }
    assert_equal '<div class="base final">Smart</div>', html
  end
  
  def test_regular_attributes_render_correctly
    html = render { 
      div("Attributed", id: "unique-123", title: "Hover me", tabindex: "0") 
    }
    assert_equal '<div id="unique-123" title="Hover me" tabindex="0">Attributed</div>', html
  end
  
  def test_data_attributes_with_underscores_become_hyphens
    html = render { 
      div("Data Rich", data: { 
        user_id: 42, 
        controller_name: "stimulus",
        turbo_frame: "modal"
      }) 
    }
    assert_equal '<div data-user-id="42" data-controller-name="stimulus" data-turbo-frame="modal">Data Rich</div>', html
  end
  
  def test_aria_attributes_for_accessibility
    html = render { 
      button("Menu", aria: { 
        label: "Open navigation",
        expanded: "false",
        controls: "nav-menu"
      }) 
    }
    assert_equal '<button aria-label="Open navigation" aria-expanded="false" aria-controls="nav-menu">Menu</button>', html
  end
  
  def test_boolean_attributes_render_without_value
    html = render { input(type: "checkbox", checked: true, disabled: true) }
    assert_equal '<input type="checkbox" checked disabled>', html
  end
  
  def test_boolean_attributes_false_omits_attribute
    html = render { input(type: "text", disabled: false, required: false) }
    assert_equal '<input type="text">', html
  end
  
  def test_kitchen_sink_all_attribute_types
    html = render {
      button("Submit",
        cs: ["btn", "btn-primary", false && "disabled"],
        id: "submit-form",
        type: "submit",
        data: { 
          confirm: "Are you sure?",
          turbo_method: "post"
        },
        aria: { 
          label: "Submit the form",
          busy: "false"
        },
        disabled: false
      )
    }
    expected = '<button class="btn btn-primary" id="submit-form" type="submit" ' \
               'data-confirm="Are you sure?" data-turbo-method="post" ' \
               'aria-label="Submit the form" aria-busy="false">Submit</button>'
    assert_equal expected, html
  end
  
	def test_deeply_nested_structure
	  html = render {
	    article {
	      header {
	        h1("Deep Dive")
	        p(cs: "author") {
	          txt "By "  # Add text inside the block
	          strong("Jane Doe")
	        }
	      }
	      section {
	        p("Content goes here...")
	      }
	    }
	  }
	  expected = "<article><header><h1>Deep Dive</h1>" \
	             '<p class="author">By <strong>Jane Doe</strong></p></header>' \
	             "<section><p>Content goes here...</p></section></article>"
	  assert_equal expected, html
	end
  
  # 💥 Bang Method Tests
  
  def test_bang_method_renders_raw_html
    html = render { div!("Hello <b>World</b>") }
    assert_equal "<div>Hello <b>World</b></div>", html
    assert_includes html, "<b>"  # Actual bold tag present
  end
  
  def test_bang_method_preserves_attributes
    html = render { 
      div!("<marquee>90s Web</marquee>", cs: "retro", id: "throwback") 
    }
    assert_equal '<div class="retro" id="throwback"><marquee>90s Web</marquee></div>', html
  end
  
  def test_bang_children_need_explicit_bang
    html = render {
      div! {
        p("This is <em>escaped</em>")
        p!("This is <em>raw</em>")
      }
    }
    expected = "<div><p>This is &lt;em&gt;escaped&lt;/em&gt;</p>" \
               "<p>This is <em>raw</em></p></div>"
    assert_equal expected, html
  end
  
  # 🔷 Void Tag Tests
  
  def test_void_tag_no_closing
    html = render { br }
    assert_equal "<br>", html
  end
  
  def test_void_tag_with_attributes
    html = render { 
      img(src: "/logo.png", alt: "Company Logo", cs: "logo", width: "200") 
    }
    assert_equal '<img class="logo" src="/logo.png" alt="Company Logo" width="200">', html
  end
  
  def test_input_with_complex_attributes
    html = render {
      input(
        cs: ["form-control", "validated"],
        type: "email",
        name: "user[email]",
        placeholder: "you@example.com",
        data: { validate: "email", message: "Invalid email" },
        aria: { describedby: "email-help" },
        required: true
      )
    }
    expected = '<input class="form-control validated" type="email" ' \
               'name="user[email]" placeholder="you@example.com" ' \
               'data-validate="email" data-message="Invalid email" ' \
               'aria-describedby="email-help" required>'
    assert_equal expected, html
  end
  
  # 🦄 Edge Cases & Special Characters
  
  def test_empty_tag_renders_correctly
    assert_equal "<div></div>", render { div }
    assert_equal "<span></span>", render { span }
  end
  
  def test_nil_content_renders_empty
    assert_equal "<p></p>", render { p(nil) }
  end
  
  def test_empty_string_content
    assert_equal "<div></div>", render { div("") }
  end
  
  def test_attribute_value_escaping_quotes_and_apostrophes
    tricky = %q{It's a "wonderful" day & <great> weather}
    html = render { div("Content", title: tricky) }
    expected_title = "It&#39;s a &quot;wonderful&quot; day &amp; &lt;great&gt; weather"
    assert_equal %Q{<div title="#{expected_title}">Content</div>}, html
  end
  
  def test_unicode_and_emoji_support
    html = render { 
      div("Hello 世界 🌍", cs: "international", lang: "zh") 
    }
    assert_equal '<div class="international" lang="zh">Hello 世界 🌍</div>', html
  end
  
def test_false_vs_string_false_in_aria
  html = render { div("Test", aria: { expanded: "false", hidden: false }) }
  assert_equal '<div aria-expanded="false">Test</div>', html  # Only expanded renders, hidden omitted
end

  # Add these tests to your existing JoysTagsTest class

# 🎯 Underscore to Dash Conversion Tests

def test_underscore_to_dash_conversion_basic_attributes
  html = render { meta(accept_charset: "UTF-8") }
  assert_equal '<meta accept-charset="UTF-8">', html
end

def test_underscore_to_dash_conversion_multiple_underscores
  html = render { meta(http_equiv: "Content-Type", some_long_attribute_name: "value") }
  assert_equal '<meta http-equiv="Content-Type" some-long-attribute-name="value">', html
end

def test_underscore_to_dash_conversion_with_regular_tags
  html = render { div("Content", cross_origin: "anonymous", accept_charset: "UTF-8") }
  assert_equal '<div cross-origin="anonymous" accept-charset="UTF-8">Content</div>', html
end

def test_underscore_to_dash_conversion_with_class_attributes
  html = render { div("Content", cs: "card", accept_charset: "UTF-8") }
  assert_equal '<div class="card" accept-charset="UTF-8">Content</div>', html
end

def test_data_attributes_nested_underscore_conversion
  html = render { div("Content", data: {user_name: "john", toggle_state: "active"}) }
  assert_equal '<div data-user-name="john" data-toggle-state="active">Content</div>', html
end

def test_aria_attributes_nested_underscore_conversion
  html = render { button("Click", aria: {expanded_state: true, has_popup: "menu"}) }
  assert_equal '<button aria-expanded-state="true" aria-has-popup="menu">Click</button>', html
end

def test_mixed_attributes_with_underscores_and_data
  html = render do
    div("Content", 
        accept_charset: "UTF-8",
        data: {user_id: 123, session_token: "abc"},
        aria: {label_text: "Close button"})
  end
  expected = '<div accept-charset="UTF-8" data-user-id="123" data-session-token="abc" aria-label-text="Close button">Content</div>'
  assert_equal expected, html
end

def test_void_tags_with_underscore_attributes
  html = render { input(accept_charset: "UTF-8", form_target: "_blank", type: "text") }
  assert_equal '<input accept-charset="UTF-8" form-target="_blank" type="text">', html
end

def test_boolean_attributes_with_underscores
  html = render { input(type: "text", auto_focus: true) }
  assert_equal '<input type="text" autofocus>', html  # autofocus, not auto-focus
end

def test_underscore_conversion_preserves_original_attribute_behavior
  # Test that regular attributes without underscores still work
  html = render { div("Content", id: "main", class: "container", title: "tooltip") }
  assert_equal '<div id="main" class="container" title="tooltip">Content</div>', html
end

def test_underscore_conversion_with_bang_methods
  html = render { div!("<b>Bold</b>", accept_charset: "UTF-8") }
  assert_equal '<div accept-charset="UTF-8"><b>Bold</b></div>', html
end

def test_complex_data_aria_attribute_scenarios
  html = render do
    button("Advanced Button",
           cs: "btn-primary",
           data: {
             controller: "form_handler",
             target_url: "/submit", 
             confirm_message: "Are you sure?"
           },
           aria: {
             described_by: "help-text",
             expanded_state: false,  # This gets omitted
             has_popup: true
           },
           form_method: "post")
  end
  
  expected = '<button class="btn-primary" ' +
             'data-controller="form_handler" ' +
             'data-target-url="/submit" ' +
             'data-confirm-message="Are you sure?" ' +
             'aria-described-by="help-text" ' +
             'aria-has-popup="true" ' +
             'form-method="post">Advanced Button</button>'
  
  assert_equal expected, html
end

def test_debug_aria_false
  html = render { div("Test", aria: {expanded_state: false}) }
  assert_equal '<div>Test</div>', html  # Boolean false omitted entirely
end

def test_edge_case_single_underscore_attributes
  html = render { div("Content", _private: "value", __internal: "data") }
  assert_equal '<div -private="value" --internal="data">Content</div>', html
end

def test_edge_case_trailing_underscore_attributes
  html = render { div("Content", trailing_: "value", ending__: "data") }
  assert_equal '<div trailing-="value" ending--="data">Content</div>', html
end

def test_no_conversion_for_attributes_without_underscores
  html = render { div("Content", id: "test", title: "tooltip", role: "button") }
  assert_equal '<div id="test" title="tooltip" role="button">Content</div>', html
end
  

end
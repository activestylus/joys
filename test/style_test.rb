require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

class JoysStyleTest < Minitest::Test
  def setup
    # Clear any existing styles
    Joys.instance_variable_set(:@compiled_styles, {})
    Joys.instance_variable_set(:@consolidated_cache, {})
    
    # Mock current_component and current_page
    Joys.define_singleton_method(:current_component) { 'comp_test_component' }
    Joys.define_singleton_method(:current_page) { nil }
    
    # Create a mock renderer with proper initialization
    @renderer = Object.new
    @renderer.extend(Joys::Render::Helpers)
    @renderer.instance_variable_set(:@current_page, nil)
    
    # Set up temporary directory for external styles testing
    @temp_dir = Dir.mktmpdir('joys_test')
    @original_css_path = Joys.css_path if defined?(Joys.css_path)
    
    # Set up css_path method if it doesn't exist
    unless Joys.respond_to?(:css_path)
      Joys.define_singleton_method(:css_path) { @css_path }
      Joys.define_singleton_method(:css_path=) { |path| @css_path = path }
    end
    
    Joys.css_path = @temp_dir
  end
  
  def teardown
    # Clean up temporary directory
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
    
    # Restore original css_path
    if @original_css_path
      Joys.css_path = @original_css_path
    else
      Joys.css_path = nil
    end
  end
  def test_external_styles_file_creation
    # Set up test components with styles
    components = ['comp_header', 'comp_footer']
    
    components.each_with_index do |comp, i|
      Joys.compiled_styles[comp] = {
        base_css: [".#{comp} { color: color#{i}; }"],
        media_queries: {
          "m-min-768" => [".#{comp} { font-size: #{16 + i}px; }"]
        }
      }
    end
    
    # Generate external styles
    html_output = Joys::Styles.render_external_styles(components)
    
    # Check that HTML link tag is correct
    expected_filename = components.sort.join(',')
    expected_html = "<link rel=\"stylesheet\" href=\"/css/#{expected_filename}.css\">"
    assert_equal expected_html, html_output, "Should return correct HTML link tag"
    
    # Check that CSS file was actually created
    css_file_path = File.join(@temp_dir, "#{expected_filename}.css")
    assert File.exist?(css_file_path), "CSS file should be created"
    
    # Check CSS file content
    css_content = File.read(css_file_path)
    assert_includes css_content, ".comp_header { color: color0; }", "Should include header styles"
    assert_includes css_content, ".comp_footer { color: color1; }", "Should include footer styles"
    assert_includes css_content, "@media (min-width: 768px)", "Should include media queries"
  end
  
  def test_external_styles_caching
    components = ['comp_button']
    
    Joys.compiled_styles['comp_button'] = {
      base_css: [".btn { padding: 10px; }"],
      media_queries: {}
    }
    
    # First call should create file
    html1 = Joys::Styles.render_external_styles(components)
    css_file_path = File.join(@temp_dir, "comp_button.css")
    original_mtime = File.mtime(css_file_path)
    
    # Wait a bit to ensure different mtime if file were recreated
    sleep 0.01
    
    # Second call should not recreate file (caching)
    html2 = Joys::Styles.render_external_styles(components)
    new_mtime = File.mtime(css_file_path)
    
    assert_equal html1, html2, "Should return same HTML"
    assert_equal original_mtime, new_mtime, "File should not be recreated (cached)"
  end
  
  def test_external_styles_with_empty_components
    # Test edge case with no components
    html_output = Joys::Styles.render_external_styles([])
    assert_equal "", html_output, "Should return empty string for no components"
    
    # Ensure no files were created
    css_files = Dir.glob(File.join(@temp_dir, "*.css"))
    assert_empty css_files, "Should not create any CSS files"
  end
  
  def test_external_styles_directory_creation
    # Test with nested directory that doesn't exist
    nested_dir = File.join(@temp_dir, "nested", "css")
    Joys.css_path = nested_dir
    
    components = ['comp_test']
    Joys.compiled_styles['comp_test'] = {
      base_css: [".test { color: red; }"],
      media_queries: {}
    }
    
    # Should create nested directories
    html_output = Joys::Styles.render_external_styles(components)
    
    assert Dir.exist?(nested_dir), "Should create nested directory structure"
    
    css_file_path = File.join(nested_dir, "comp_test.css")
    assert File.exist?(css_file_path), "Should create CSS file in nested directory"
    
    expected_html = "<link rel=\"stylesheet\" href=\"/css/comp_test.css\">"
    assert_equal expected_html, html_output, "Should return correct HTML link tag"
  end
  
  def test_external_styles_complex_content
    # Test with complex CSS including media queries, container queries, etc.
    @renderer.instance_eval do
      styles do
        css ".complex { color: blue; border: 1px solid #ccc; }"
        media_min(768, ".complex { padding: 2rem; }")
        media_max(1024, ".complex { font-size: 14px; }")
        container_min(300, ".complex { display: grid; }")
        named_container_min("sidebar", 250, ".complex { width: 100%; }")
      end
    end
    
    components = ['comp_test_component']
    html_output = Joys::Styles.render_external_styles(components)
    
    css_file_path = File.join(@temp_dir, "comp_test_component.css")
    css_content = File.read(css_file_path)
    
    # Check that all types of styles are included
    assert_includes css_content, ".complex { color: blue; border: 1px solid #ccc; }", "Should include base CSS"
    assert_includes css_content, "@media (max-width: 1024px)", "Should include max-width media query"
    assert_includes css_content, "@media (min-width: 768px)", "Should include min-width media query"
    assert_includes css_content, "@container (min-width: 300px)", "Should include container query"
    assert_includes css_content, "@container sidebar (min-width: 250px)", "Should include named container query"
    
    # Verify proper CSS structure and ordering
    media_max_pos = css_content.index("@media (max-width: 1024px)")
    media_min_pos = css_content.index("@media (min-width: 768px)")
    container_pos = css_content.index("@container (min-width: 300px)")
    
    assert media_max_pos < media_min_pos, "max-width queries should come before min-width queries"
    assert media_min_pos < container_pos, "media queries should come before container queries"
  end

  
  def test_basic_css_compilation
    @renderer.instance_eval do
      styles do
        css ".test { color: red; }"
        css ".another { font-size: 16px; }"
      end
    end
    
    compiled = Joys.compiled_styles['comp_test_component']
    
    refute_nil compiled, "Styles should be compiled"
    assert_equal 2, compiled[:base_css].length, "Should have 2 base CSS rules"
    assert_includes compiled[:base_css][0], ".test { color: red; }", "First CSS rule should match"
  end
  
  def test_media_queries
    @renderer.instance_eval do
      styles do
        css ".base { width: 100%; }"
        media_min(768, ".responsive { display: flex; }")
        media_max(1024, ".mobile { font-size: 14px; }")
        media_minmax(480, 768, ".tablet { padding: 1rem; }")
      end
    end
    
    compiled = Joys.compiled_styles['comp_test_component']
    media_queries = compiled[:media_queries]
    
    refute_nil media_queries, "Media queries should exist"
    
    puts "DEBUG: Media queries keys: #{media_queries.keys.inspect}" if media_queries
    
    assert media_queries.key?('m-min-768'), "Should have min-width query"
    assert media_queries.key?('m-max-1024'), "Should have max-width query"
    assert media_queries.key?('m-minmax-480-768'), "Should have minmax query"
  end
  
  def test_container_queries
    @renderer.instance_eval do
      styles do
        container_min(300, ".card { grid-template-columns: 1fr; }")
        container_max(600, ".card { padding: 0.5rem; }")
        container_minmax(400, 800, ".card { margin: 1rem; }")
      end
    end
    
    compiled = Joys.compiled_styles['comp_test_component']
    queries = compiled[:media_queries]
    
    puts "DEBUG: Container queries keys: #{queries.keys.inspect}" if queries
    
    assert queries.key?('c-min-300'), "Should have container min query"
    assert queries.key?('c-max-600'), "Should have container max query" 
    assert queries.key?('c-minmax-400-800'), "Should have container minmax query"
  end
  
  def test_named_container_queries
    @renderer.instance_eval do
      styles do
        named_container_min("sidebar", 250, ".nav { display: block; }")
        named_container_max("main", 1200, ".content { max-width: 100%; }")
        named_container_minmax("modal", 300, 800, ".dialog { width: 90%; }")
      end
    end
    
    compiled = Joys.compiled_styles['comp_test_component']
    queries = compiled[:media_queries]
    
    puts "DEBUG: Named container queries keys: #{queries.keys.inspect}" if queries
    
    assert queries.key?('c-sidebar-min-250'), "Should have named container min"
    assert queries.key?('c-main-max-1200'), "Should have named container max"
    assert queries.key?('c-modal-minmax-300-800'), "Should have named container minmax"
  end
  
  def test_scoped_styles
    # Test unscoped (default)
    @renderer.instance_eval do
      styles do
        css ".unscoped { color: blue; }"
      end
    end
    
    unscoped = Joys.compiled_styles['comp_test_component'][:base_css][0]
    
    # Clear and test scoped
    Joys.compiled_styles.clear
    @renderer.instance_eval do
      styles(scoped: true) do
        css ".scoped { color: red; }"
      end
    end
    
    scoped = Joys.compiled_styles['comp_test_component'][:base_css][0]
    
    assert_equal ".unscoped { color: blue; }", unscoped, "Unscoped should be unchanged"
    assert_includes scoped, ".comp-test-component .scoped", "Scoped should have prefix"
  end
  
  def test_multiple_components
    # Component 1
    Joys.define_singleton_method(:current_component) { 'comp_card' }
    renderer1 = create_renderer
    renderer1.instance_eval do
      styles do
        css ".card { border: 1px solid #ccc; }"
        media_min(768, ".card { padding: 2rem; }")
      end
    end
    
    # Component 2  
    Joys.define_singleton_method(:current_component) { 'comp_button' }
    renderer2 = create_renderer
    renderer2.instance_eval do
      styles do
        css ".btn { padding: 0.5rem; }"
        container_min(200, ".btn { width: 100%; }")
      end
    end
    
    compiled_styles = Joys.compiled_styles
    assert compiled_styles.key?('comp_card'), "Should have card component"
    assert compiled_styles.key?('comp_button'), "Should have button component"
    
    card_css = compiled_styles['comp_card'][:base_css]
    button_css = compiled_styles['comp_button'][:base_css]
    
    assert_includes card_css[0], "border: 1px solid", "Card should have border"
    assert_includes button_css[0], "padding: 0.5rem", "Button should have padding"
  end
  
  def test_consolidated_rendering
    # Set up multiple components with different query types
    components = ['comp_a', 'comp_b', 'comp_c']
    components.each_with_index do |comp, i|
      Joys.compiled_styles[comp] = {
        base_css: [".#{comp} { color: color#{i}; }"],
        media_queries: {
          "m-min-768" => [".#{comp} { font-size: #{16 + i}px; }"],
          "c-min-300" => [".#{comp} { padding: #{i}rem; }"]
        }
      }
    end
    
    # Test consolidated output
    consolidated = Joys::Styles.send(:render_consolidated_styles, components)
    
    puts "DEBUG: Consolidated CSS: #{consolidated.inspect}"
    
    refute_nil consolidated, "Should generate consolidated CSS"
    assert_includes consolidated, "comp_a", "Should include first component"
    assert_includes consolidated, "@media", "Should include media queries"
    assert_includes consolidated, "@container", "Should include container queries"
    
    # Test caching
    cached = Joys::Styles.send(:render_consolidated_styles, components)
    assert_equal consolidated, cached, "Should return cached result"
  end
  
  def test_edge_cases
    # Test empty styles block
    @renderer.instance_eval do
      styles do
        # Empty block
      end
    end
    
    compiled = Joys.compiled_styles['comp_test_component']
    assert_equal 0, compiled[:base_css].length, "Empty block should have no CSS"
    
    # Test duplicate CSS
    Joys.compiled_styles.clear
    @renderer.instance_eval do
      styles do
        css ".duplicate { color: red; }"
        css ".duplicate { color: red; }"  # Exact duplicate
      end
    end
    
    compiled = Joys.compiled_styles['comp_test_component']
    assert_equal 2, compiled[:base_css].length, "Should allow duplicates during compilation"
  end
  
  def test_css_output_format
    # Test that the actual CSS output is correct
    @renderer.instance_eval do
      styles do
        css ".base { color: red; }"
        media_min(768, ".responsive { display: flex; }")
        container_min(300, ".card { padding: 1rem; }")
        named_container_min("sidebar", 250, ".nav { width: 100%; }")
      end
    end
    
    consolidated = Joys::Styles.send(:render_consolidated_styles, ['comp_test_component'])
    
    puts "DEBUG: CSS output format test - consolidated: #{consolidated.inspect}"
    
    # Check base CSS
    assert_includes consolidated, ".base { color: red; }", "Should include base CSS"
    
    # Check media query format
    assert_includes consolidated, "@media (min-width: 768px)", "Should include proper media query"
    assert_includes consolidated, ".responsive { display: flex; }", "Should include media query content"
    
    # Check container query format  
    assert_includes consolidated, "@container (min-width: 300px)", "Should include proper container query"
    assert_includes consolidated, ".card { padding: 1rem; }", "Should include container query content"
    
    # Check named container query format
    assert_includes consolidated, "@container sidebar (min-width: 250px)", "Should include named container query"
    assert_includes consolidated, ".nav { width: 100%; }", "Should include named container content"
  end
  
  private
  
  def create_renderer
    renderer = Object.new
    renderer.extend(Joys::Render::Helpers)
    renderer.instance_variable_set(:@current_page, nil)
    renderer
  end
end
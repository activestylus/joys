require 'minitest/autorun'
require 'minitest/pride'
require 'tmpdir'
require 'fileutils'
require 'json'
require_relative '../lib/joys'  # Use real Joys DSL
require_relative '../lib/joys/ssg'

module Joys
  module SSG
    class TestSSG < Minitest::Test
      def setup
        @temp_dir = Dir.mktmpdir
        @content_dir = File.join(@temp_dir, 'content')
        @output_dir = File.join(@temp_dir, 'dist')
        @original_output_dir = Joys::SSG.output_dir
        Joys::SSG.output_dir = @output_dir
        
        # Clear Joys registry to avoid cross-test pollution - use correct variable names
        Joys.instance_variable_set(:@templates, {}) if Joys.instance_variable_defined?(:@templates)
        Joys.instance_variable_set(:@layouts, {}) if Joys.instance_variable_defined?(:@layouts)
        Joys.instance_variable_set(:@cache, {}) if Joys.instance_variable_defined?(:@cache)
      end

      def teardown
        FileUtils.rm_rf(@temp_dir)
        Joys::SSG.output_dir = @original_output_dir
        # Clear Joys registry after tests - use correct variable names  
        Joys.instance_variable_set(:@templates, {}) if Joys.instance_variable_defined?(:@templates)
        Joys.instance_variable_set(:@layouts, {}) if Joys.instance_variable_defined?(:@layouts)
        Joys.instance_variable_set(:@cache, {}) if Joys.instance_variable_defined?(:@cache)
      end

      def create_test_structure
        FileUtils.mkdir_p(File.join(@content_dir, 'default'))
        FileUtils.mkdir_p(File.join(@content_dir, 'blog'))
        FileUtils.mkdir_p(File.join(@content_dir, 'default/_components'))
        FileUtils.mkdir_p(File.join(@content_dir, 'default/_layouts'))
        FileUtils.mkdir_p(File.join(@temp_dir, 'hash'))
        FileUtils.mkdir_p(File.join(@temp_dir, 'public'))
      end

      def test_basic_build
        create_test_structure
        
        # Create a simple page using real Joys DSL
        File.write(File.join(@content_dir, 'default/index.rb'), %{
          Joys.html { h1 "Hello World" }
        })

        # Create a layout using real Joys DSL
        File.write(File.join(@content_dir, 'default/_layouts/main.rb'), %{
          Joys.define :layout, :main do
            html { head { title "Test" }; body { pull(:body) } }
          end
        })

        built_files = Joys::SSG.build(@content_dir, @output_dir)

        assert_equal 1, built_files.size
        assert_includes built_files, 'index.html'
        assert File.exist?(File.join(@output_dir, 'index.html'))
        
        content = File.read(File.join(@output_dir, 'index.html'))
        assert_includes content, 'Hello World'
        assert_includes content, '<h1>'
      end

      def test_multiple_domains
        create_test_structure
        
        # Create pages in different domains
        File.write(File.join(@content_dir, 'default/index.rb'), %{
          Joys.html { h1 "Default Domain" }
        })
        
        File.write(File.join(@content_dir, 'blog/posts.rb'), %{
          Joys.html { h1 "Blog Posts" }
        })

        built_files = Joys::SSG.build(@content_dir, @output_dir)

        assert_equal 2, built_files.size
        assert File.exist?(File.join(@output_dir, 'index.html'))
        assert File.exist?(File.join(@output_dir, 'blog/posts/index.html'))
        
        # Check content
        default_content = File.read(File.join(@output_dir, 'index.html'))
        assert_includes default_content, 'Default Domain'
        
        blog_content = File.read(File.join(@output_dir, 'blog/posts/index.html'))
        assert_includes blog_content, 'Blog Posts'
      end

      def test_nested_pages
        create_test_structure
        
        FileUtils.mkdir_p(File.join(@content_dir, 'default/nested'))
        File.write(File.join(@content_dir, 'default/nested/page.rb'), %{
          Joys.html { h1 "Nested Page" }
        })

        built_files = Joys::SSG.build(@content_dir, @output_dir)

        assert_includes built_files, 'nested/page/index.html'
        assert File.exist?(File.join(@output_dir, 'nested/page/index.html'))
        
        content = File.read(File.join(@output_dir, 'nested/page/index.html'))
        assert_includes content, 'Nested Page'
      end

      def test_components_and_layouts_loading
        create_test_structure
        
        # Create component file using real Joys DSL
        File.write(File.join(@content_dir, 'default/_components/header.rb'), %{
          Joys.define :comp, :header do |title|
            header { h2 title }
          end
        })
        
        # Create layout file using real Joys DSL
        File.write(File.join(@content_dir, 'default/_layouts/main.rb'), %{
          Joys.define :layout, :main do
            html {
              head { title "Test Site" }
              body { pull(:content) }
            }
          end
        })

        # Create page that uses them
        File.write(File.join(@content_dir, 'default/index.rb'), %{
          Joys.html do
          layout(:main) do
            push(:content) do
              comp(:header, "Welcome")
              h1 "Main Content"
            end
          end
          end
        })

        built_files = Joys::SSG.build(@content_dir, @output_dir)
        
        assert_equal 1, built_files.size
        content = File.read(File.join(@output_dir, 'index.html'))
        
        # Should contain the layout structure
        assert_includes content, '<html>'
        assert_includes content, '<head>'
        assert_includes content, '<title>Test Site</title>'
        assert_includes content, '<body>'
        
        # Should contain the component output
        assert_includes content, '<header>'
        assert_includes content, '<h2>Welcome</h2>'
        
        # Should contain the main content
        assert_includes content, '<h1>Main Content</h1>'
      end

      def test_asset_copying
        create_test_structure
        
        # Create public assets (global assets)
        FileUtils.mkdir_p(File.join(@temp_dir, 'public/css'))
        File.write(File.join(@temp_dir, 'public/style.css'), 'body { color: blue; }')
        File.write(File.join(@temp_dir, 'public/css/main.css'), 'h1 { color: red; }')
        File.write(File.join(@temp_dir, 'public/favicon.ico'), 'fake-favicon-data')

        # Create page
        File.write(File.join(@content_dir, 'default/index.rb'), %{
          Joys.html { h1 "Test" }
        })

        # Change to temp dir for asset copying to work
        Dir.chdir(@temp_dir) do
          Joys::SSG.build(@content_dir, @output_dir)
        end

        # Global assets should be copied to root
        assert File.exist?(File.join(@output_dir, 'style.css'))
        assert File.exist?(File.join(@output_dir, 'css/main.css'))
        assert File.exist?(File.join(@output_dir, 'favicon.ico'))
        assert_equal 'body { color: blue; }', File.read(File.join(@output_dir, 'style.css'))
        assert_equal 'fake-favicon-data', File.read(File.join(@output_dir, 'favicon.ico'))
      end

      def test_dependency_tracking
        create_test_structure
        
        # Create layout and component
        File.write(File.join(@content_dir, 'default/_layouts/main.rb'), %{
          Joys.define :layout, :main do
            html { body { pull(:content) } }
          end
        })
        
        File.write(File.join(@content_dir, 'default/_components/header.rb'), %{
          Joys.define :comp, :header do |title|
            header { h1 title }
          end
        })
        
        File.write(File.join(@content_dir, 'default/index.rb'), %{
          layout(:main) do
            push(:content) do
              comp(:header, "Test Title")
              p "Content"
            end
          end
        })

        Joys::SSG.build(@content_dir, @output_dir)

        deps_file = File.join(@output_dir, '.ssg_dependencies.json')
        assert File.exist?(deps_file)
        
        deps = JSON.parse(File.read(deps_file))
        page_file = File.join(@content_dir, 'default/index.rb')
        
        assert deps['templates'].key?(page_file)
        assert_includes deps['templates'][page_file]['layouts'], 'main'
        assert_includes deps['templates'][page_file]['components'], 'header'
      end

      def test_force_rebuild
        create_test_structure
        
        File.write(File.join(@content_dir, 'default/index.rb'), %{
          Joys.html { h1 "Original" }
        })

        # First build
        Joys::SSG.build(@content_dir, @output_dir)
        original_content = File.read(File.join(@output_dir, 'index.html'))

        # Modify and rebuild with force
        File.write(File.join(@content_dir, 'default/index.rb'), %{
          Joys.html { h1 "Modified" }
        })

        Joys::SSG.build(@content_dir, @output_dir, force: true)
        new_content = File.read(File.join(@output_dir, 'index.html'))

        refute_equal original_content, new_content
        assert_includes new_content, 'Modified'
      end

      def test_skip_special_files
        create_test_structure
        
        # Create files that should be skipped
        File.write(File.join(@content_dir, 'default/_components/header.rb'), '# Component')
        File.write(File.join(@content_dir, 'default/_layouts/main.rb'), '# Layout')
        
        # Create normal page
        File.write(File.join(@content_dir, 'default/index.rb'), %{
          Joys.html { h1 "Index" }
        })

        built_files = Joys::SSG.build(@content_dir, @output_dir)

        # Should only build the index page
        assert_equal 1, built_files.size
        assert_includes built_files, 'index.html'
      end
    end

    class TestPageContext < Minitest::Test
      def setup
        @temp_dir = Dir.mktmpdir
        @content_dir = File.join(@temp_dir, 'content')
        @temp_file = File.join(@content_dir, 'default', 'test_page.rb')
        FileUtils.mkdir_p(File.dirname(@temp_file))
        @context = PageContext.new(@temp_file, @content_dir)
        
        # Clear Joys registry - use correct variable names
        Joys.instance_variable_set(:@templates, {}) if Joys.instance_variable_defined?(:@templates)
        Joys.instance_variable_set(:@layouts, {}) if Joys.instance_variable_defined?(:@layouts)
        Joys.instance_variable_set(:@cache, {}) if Joys.instance_variable_defined?(:@cache)
      end

      def teardown
        FileUtils.rm_rf(@temp_dir)
        Joys.instance_variable_set(:@templates, {}) if Joys.instance_variable_defined?(:@templates)
        Joys.instance_variable_set(:@layouts, {}) if Joys.instance_variable_defined?(:@layouts)
        Joys.instance_variable_set(:@cache, {}) if Joys.instance_variable_defined?(:@cache)
      end

      def test_dependency_tracking
        # Create actual components and layouts
        Joys.define :layout, :main do
          html { body { pull(:content) } }
        end
        
        Joys.define :comp, :header do
          header { h1 "Header" }
        end
        
        Joys.define :comp, :footer do |text|
          footer { p text }
        end

        @context.layout(:main)
        @context.comp(:header)
        @context.comp(:footer, 'Copyright 2024')

        assert_includes @context.used_dependencies['layouts'], 'main'
        assert_includes @context.used_dependencies['components'], 'header' 
        assert_includes @context.used_dependencies['components'], 'footer'
      end

      def test_html_method
        result = @context.html { h1 "Content" }
        assert_includes result, "<h1>Content</h1>"
      end

      def test_layout_method
        Joys.define :layout, :main do
          html { 
            head { title "Test" }
            body { pull(:body) }  # Use pull(:body) instead of direct execution
          }
        end
        
        result = @context.layout(:main) do
          push(:body) { h1 "Content" }  # Use push(:body) to send content to the layout
        end
        
        assert_includes result, '<html>'
        assert_includes result, '<title>Test</title>'
        assert_includes result, '<h1>Content</h1>'
      end

      def test_comp_method
        Joys.define :comp, :header do |title|
          header { h2 title }
        end
        
        result = @context.comp(:header, 'Test Title')
        assert_includes result, '<header>'
        assert_includes result, '<h2>Test Title</h2>'
      end

      def test_params_and_session
        assert_equal({}, @context.params)
        assert_equal({}, @context.session)
      end

      def test_data_dependency_tracking
        # This would normally interact with Joys::Data
        @context.data(:posts)
        
        assert_includes @context.used_dependencies['data'], 'posts'
      end

      def test_pagination_setup
        page_info = { url_path: '/blog/', output_path: 'blog/index.html' }
        @context.setup_pagination_capture(page_info)
        
        assert @context.instance_variable_get(:@capturing_pagination)
        assert_equal page_info, @context.instance_variable_get(:@base_page)
      end

      def test_asset_path_helper
        # Create fake manifest
        @context.instance_variable_set(:@asset_manifest, {
          'default/style.css' => '/assets/style-a1b2c3d4.css',
          'blog_mysite_com/theme.css' => '/blog_mysite_com/assets/theme-e5f6g7h8.css'
        })
        
        # Test default domain
        assert_equal '/assets/style-a1b2c3d4.css', @context.asset_path('style.css')
        
        # Test missing asset (fallback)
        assert_equal '/assets/missing.css', @context.asset_path('missing.css')
      end

      def test_asset_url_helper
        @context.instance_variable_set(:@asset_manifest, {
          'default/style.css' => '/assets/style-a1b2c3d4.css'
        })
        @context.instance_variable_set(:@site_url, 'https://example.com')
        
        assert_equal 'https://example.com/assets/style-a1b2c3d4.css', @context.asset_url('style.css')
      end

      def test_domain_extraction_from_path
        # Test default domain
        default_path = File.join(@content_dir, 'default', 'index.rb')
        context = PageContext.new(default_path, @content_dir)
        domain = context.send(:extract_domain_from_path, default_path)
        assert_equal 'default', domain
        
        # Test blog domain
        blog_path = File.join(@content_dir, 'blog_mysite_com', 'posts', 'index.rb')
        FileUtils.mkdir_p(File.dirname(blog_path))
        context = PageContext.new(blog_path, @content_dir)
        domain = context.send(:extract_domain_from_path, blog_path)
        assert_equal 'blog_mysite_com', domain
        
        # Test malformed path
        invalid_context = PageContext.new('invalid/path.rb', @content_dir)
        domain = invalid_context.send(:extract_domain_from_path, 'invalid/path.rb')
        assert_equal 'default', domain
      end

      def test_paginate_with_collection
        # Create mock data page
        items = (1..15).map { |i| { id: i, title: "Post #{i}" } }
        
        # Mock the Joys::Data::Page class if it doesn't exist
        unless defined?(Joys::Data::Page)
          page_class = Class.new do
            attr_reader :items, :current_page, :total_pages, :total_items
            
            def initialize(items, current_page, total_pages, total_items)
              @items = items
              @current_page = current_page
              @total_pages = total_pages
              @total_items = total_items
            end
          end
          
          # Define it in a way that can be referenced
          Joys.const_set(:Data, Module.new) unless defined?(Joys::Data)
          Joys::Data.const_set(:Page, page_class) unless defined?(Joys::Data::Page)
        end
        
        @context.current_pagination_page = Joys::Data::Page.new(items[0, 5], 1, 3, 15)
        
        result = @context.paginate(items, per_page: 5) do |page|
          "Page #{page.current_page} has #{page.items.size} items"
        end

        assert_includes result, "Page 1 has 5 items"
      end

      def test_paginate_error_handling
        error = assert_raises(ArgumentError) do
          @context.paginate([], per_page: 0) { |page| "test" }
        end
        assert_match /per_page must be positive/, error.message

        error = assert_raises(ArgumentError) do
          @context.paginate([], per_page: -5) { |page| "test" }
        end
        assert_match /per_page must be positive/, error.message
      end
    end

    class TestPageObject < Minitest::Test
      def test_initialization
        page = PageObject.new(
          posts: ['post1', 'post2'],
          current_page: 2,
          total_pages: 5
        )

        assert_equal ['post1', 'post2'], page.posts
        assert_equal 2, page.current_page
        assert_equal 5, page.total_pages
      end

      def test_method_missing
        page = PageObject.new(custom_attr: 'value', number: 42)
        
        assert_equal 'value', page.custom_attr
        assert_equal 42, page.number
      end

      def test_respond_to_missing
        page = PageObject.new(custom_attr: 'value')
        
        assert page.respond_to?(:custom_attr)
        refute page.respond_to?(:nonexistent_attr)
      end

      def test_to_h
        attrs = { posts: [], current_page: 1, total_pages: 1 }
        page = PageObject.new(**attrs)
        
        assert_equal attrs, page.to_h
      end
    end

    class TestMockDataQuery < Minitest::Test
      def test_method_missing_returns_self
        query = Joys::SSG::MockDataQuery.new
        
        assert_equal query, query.where(id: 1)
        assert_equal query, query.order(:name)
        assert_equal query, query.limit(10)
      end

      def test_terminal_methods
        query = Joys::SSG::MockDataQuery.new
        
        assert_equal [], query.all
        assert_equal 0, query.count
      end
    end

    class TestHelperMethods < Minitest::Test
      def setup
        @ssg = Class.new { extend Joys::SSG }
      end

      def test_file_path_to_url
        assert_equal '/', @ssg.send(:file_path_to_url, 'index.rb')
        assert_equal '/about/', @ssg.send(:file_path_to_url, 'about.rb')
        assert_equal '/blog/posts/', @ssg.send(:file_path_to_url, 'blog/posts.rb')
        assert_equal '/:id/', @ssg.send(:file_path_to_url, '_id.rb')
      end

      def test_url_to_output_path
        assert_equal 'index.html', @ssg.send(:url_to_output_path, 'default', '/')
        assert_equal 'about/index.html', @ssg.send(:url_to_output_path, 'default', '/about/')
        assert_equal 'blog/index.html', @ssg.send(:url_to_output_path, 'blog', '/')
        assert_equal 'blog/posts/index.html', @ssg.send(:url_to_output_path, 'blog', '/posts/')
      end

      def test_generate_pagination_path
        base_path = 'blog/index.html'
        
        assert_equal 'blog/index.html', @ssg.send(:generate_pagination_path, base_path, 1)
        assert_equal 'blog/page-2/index.html', @ssg.send(:generate_pagination_path, base_path, 2)
        assert_equal 'blog/page-5/index.html', @ssg.send(:generate_pagination_path, base_path, 5)
      end

      def test_analyze_page_file
        content_dir = '/tmp/content'
        file_path = '/tmp/content/blog/posts.rb'
        
        result = @ssg.send(:analyze_page_file, file_path, content_dir)
        
        expected = {
          file_path: file_path,
          domain: 'blog',
          url_path: '/posts/',
          output_path: 'blog/posts/index.html'
        }
        
        assert_equal expected, result
      end

      def test_analyze_page_file_index
        content_dir = '/tmp/content'
        file_path = '/tmp/content/default/index.rb'
        
        result = @ssg.send(:analyze_page_file, file_path, content_dir)
        
        expected = {
          file_path: file_path,
          domain: 'default', 
          url_path: '/',
          output_path: 'index.html'
        }
        
        assert_equal expected, result
      end

      def test_analyze_page_file_invalid
        content_dir = '/tmp/content'
        file_path = '/tmp/other/file.rb'  # Outside content_dir
        
        result = @ssg.send(:analyze_page_file, file_path, content_dir)
        
        assert_nil result
      end
    end

    class TestAssetHandling < Minitest::Test
      def setup
        @temp_dir = Dir.mktmpdir
        @content_dir = File.join(@temp_dir, 'content')
        @output_dir = File.join(@temp_dir, 'dist')
        @original_output_dir = Joys::SSG.output_dir
        Joys::SSG.output_dir = @output_dir
        
        create_asset_structure
      end

      def teardown
        FileUtils.rm_rf(@temp_dir)
        Joys::SSG.output_dir = @original_output_dir
      end

      def create_asset_structure
        # Create domain directories with assets
        FileUtils.mkdir_p(File.join(@content_dir, 'default/assets'))
        FileUtils.mkdir_p(File.join(@content_dir, 'blog_mysite_com/assets/css'))
        
        # Create global assets
        FileUtils.mkdir_p(File.join(@temp_dir, 'public/fonts'))
        File.write(File.join(@temp_dir, 'public/favicon.ico'), 'fake-favicon')
        File.write(File.join(@temp_dir, 'public/robots.txt'), 'User-agent: *')
        File.write(File.join(@temp_dir, 'public/fonts/inter.woff2'), 'fake-font-data')
        
        # Create domain-specific assets
        File.write(File.join(@content_dir, 'default/assets/style.css'), 'body { color: blue; }')
        File.write(File.join(@content_dir, 'default/assets/logo.png'), 'fake-logo-data')
        File.write(File.join(@content_dir, 'blog_mysite_com/assets/blog.css'), 'article { margin: 1rem; }')
        File.write(File.join(@content_dir, 'blog_mysite_com/assets/css/theme.css'), '.theme { background: red; }')
        
        # Create pages to trigger build
        File.write(File.join(@content_dir, 'default/index.rb'), %{
          Joys.html { h1 "Default Domain" }
        })
        File.write(File.join(@content_dir, 'blog_mysite_com/index.rb'), %{
          Joys.html { h1 "Blog Domain" }
        })
      end

      def test_global_asset_copying
        Dir.chdir(@temp_dir) do
          Joys::SSG.build(@content_dir, @output_dir)
        end
        
        # Global assets should be copied to root without hashing
        assert File.exist?(File.join(@output_dir, 'favicon.ico'))
        assert File.exist?(File.join(@output_dir, 'robots.txt'))
        assert File.exist?(File.join(@output_dir, 'fonts/inter.woff2'))
        
        # Content should be unchanged
        assert_equal 'fake-favicon', File.read(File.join(@output_dir, 'favicon.ico'))
        assert_equal 'User-agent: *', File.read(File.join(@output_dir, 'robots.txt'))
      end

      def test_domain_asset_copying_with_hashing
        Dir.chdir(@temp_dir) do
          Joys::SSG.build(@content_dir, @output_dir)
        end
        
        # Default domain assets should be in /assets/
        default_assets_dir = File.join(@output_dir, 'assets')
        assert Dir.exist?(default_assets_dir)
        
        # Blog domain assets should be in /blog_mysite_com/assets/
        blog_assets_dir = File.join(@output_dir, 'blog_mysite_com', 'assets')
        assert Dir.exist?(blog_assets_dir)
        
        # Check default domain assets (should have hashed names)
        default_files = Dir.glob("#{default_assets_dir}/**/*").select { |f| File.file?(f) }
        assert default_files.any? { |f| f.match(/style-[a-f0-9]{8}\.css/) }
        assert default_files.any? { |f| f.match(/logo-[a-f0-9]{8}\.png/) }
        
        # Check blog domain assets (should have hashed names)
        blog_files = Dir.glob("#{blog_assets_dir}/**/*").select { |f| File.file?(f) }
        assert blog_files.any? { |f| f.match(/blog-[a-f0-9]{8}\.css/) }
        assert blog_files.any? { |f| f.match(/theme-[a-f0-9]{8}\.css/) }
      end

      def test_asset_manifest_generation
        Dir.chdir(@temp_dir) do
          Joys::SSG.build(@content_dir, @output_dir)
        end
        
        manifest_file = File.join(@output_dir, '.asset_manifest.json')
        assert File.exist?(manifest_file)
        
        manifest = JSON.parse(File.read(manifest_file))
        
        # Should have entries for each domain asset
        assert manifest.key?('default/style.css')
        assert manifest.key?('default/logo.png')
        assert manifest.key?('blog_mysite_com/blog.css')
        assert manifest.key?('blog_mysite_com/css/theme.css')
        
        # Manifest values should be full URL paths with domain prefixes
        assert manifest['default/style.css'].match(/\/assets\/style-[a-f0-9]{8}\.css/)
        assert manifest['default/logo.png'].match(/\/assets\/logo-[a-f0-9]{8}\.png/)
        assert manifest['blog_mysite_com/blog.css'].match(/\/blog_mysite_com\/assets\/blog-[a-f0-9]{8}\.css/)
        assert manifest['blog_mysite_com/css/theme.css'].match(/\/blog_mysite_com\/assets\/css\/theme-[a-f0-9]{8}\.css/)
      end

      def test_asset_path_helper_integration
        Dir.chdir(@temp_dir) do
          Joys::SSG.build(@content_dir, @output_dir)
        end
        
        # Test with a page from default domain
        default_page_file = File.join(@content_dir, 'default/index.rb')
        context = Joys::SSG::PageContext.new(default_page_file, @content_dir)
        
        asset_path = context.asset_path('style.css')
        
        # Should return /assets/ path with hashed filename for default domain
        assert asset_path.start_with?('/assets/')
        assert asset_path.match(/\/assets\/style-[a-f0-9]{8}\.css/)
        
        # Test with a page from blog domain
        blog_page_file = File.join(@content_dir, 'blog_mysite_com/index.rb')
        blog_context = Joys::SSG::PageContext.new(blog_page_file, @content_dir)
        
        blog_asset_path = blog_context.asset_path('blog.css')
        
        # Should return /blog_mysite_com/assets/ path with hashed filename
        assert blog_asset_path.start_with?('/blog_mysite_com/assets/')
        assert blog_asset_path.match(/\/blog_mysite_com\/assets\/blog-[a-f0-9]{8}\.css/)
      end

      def test_consistent_hashing
        # Build twice and ensure same content gets same hash
        Dir.chdir(@temp_dir) do
          Joys::SSG.build(@content_dir, @output_dir)
        end
        
        first_manifest = JSON.parse(File.read(File.join(@output_dir, '.asset_manifest.json')))
        
        # Clean and rebuild
        FileUtils.rm_rf(@output_dir)
        
        Dir.chdir(@temp_dir) do
          Joys::SSG.build(@content_dir, @output_dir)
        end
        
        second_manifest = JSON.parse(File.read(File.join(@output_dir, '.asset_manifest.json')))
        
        # Hashes should be identical for same content
        assert_equal first_manifest, second_manifest
      end

      def test_content_change_updates_hash
        Dir.chdir(@temp_dir) do
          Joys::SSG.build(@content_dir, @output_dir)
        end
        
        original_manifest = JSON.parse(File.read(File.join(@output_dir, '.asset_manifest.json')))
        original_style_hash = original_manifest['default/style.css']
        
        # Modify the CSS content
        File.write(File.join(@content_dir, 'default/assets/style.css'), 'body { color: red; }')
        
        # Clean and rebuild
        FileUtils.rm_rf(@output_dir)
        
        Dir.chdir(@temp_dir) do
          Joys::SSG.build(@content_dir, @output_dir)
        end
        
        new_manifest = JSON.parse(File.read(File.join(@output_dir, '.asset_manifest.json')))
        new_style_hash = new_manifest['default/style.css']
        
        # Hash should be different for changed content
        refute_equal original_style_hash, new_style_hash
      end

      def test_nested_domain_assets
        # Create nested asset structure
        FileUtils.mkdir_p(File.join(@content_dir, 'default/assets/images/icons'))
        File.write(File.join(@content_dir, 'default/assets/images/icons/star.svg'), '<svg>star</svg>')
        
        Dir.chdir(@temp_dir) do
          Joys::SSG.build(@content_dir, @output_dir)
        end
        
        manifest = JSON.parse(File.read(File.join(@output_dir, '.asset_manifest.json')))
        
        # Should handle nested paths
        assert manifest.key?('default/images/icons/star.svg')
        hashed_path = manifest['default/images/icons/star.svg']
        
        # Should be full URL path for default domain
        assert hashed_path.start_with?('/assets/')
        assert hashed_path.match(/\/assets\/images\/icons\/star-[a-f0-9]{8}\.svg/)
        
        # File should exist at correct location in default domain
        relative_path = hashed_path.sub('/assets/', '')
        assert File.exist?(File.join(@output_dir, 'assets', relative_path))
      end
    end

    # Simplified tests for other functionality
    class TestIncrementalBuild < Minitest::Test
      def setup
        @temp_dir = Dir.mktmpdir
        @content_dir = File.join(@temp_dir, 'content')
        @output_dir = File.join(@temp_dir, 'dist')
        create_test_structure
        Joys::SSG.output_dir = @output_dir
        
        # Clear Joys registry - use correct variable names
        Joys.instance_variable_set(:@templates, {}) if Joys.instance_variable_defined?(:@templates)
        Joys.instance_variable_set(:@layouts, {}) if Joys.instance_variable_defined?(:@layouts)
        Joys.instance_variable_set(:@cache, {}) if Joys.instance_variable_defined?(:@cache)
      end

      def teardown
        FileUtils.rm_rf(@temp_dir)
        Joys.instance_variable_set(:@templates, {}) if Joys.instance_variable_defined?(:@templates)
        Joys.instance_variable_set(:@layouts, {}) if Joys.instance_variable_defined?(:@layouts)
        Joys.instance_variable_set(:@cache, {}) if Joys.instance_variable_defined?(:@cache)
      end

      def create_test_structure
        FileUtils.mkdir_p(File.join(@content_dir, 'default'))
        FileUtils.mkdir_p(File.join(@content_dir, 'default/_components'))
        FileUtils.mkdir_p(File.join(@content_dir, 'default/_layouts'))
      end

      def test_incremental_build_with_no_changes
        File.write(File.join(@content_dir, 'default/index.rb'), %{
          Joys.html { h1 "Test" }
        })

        # Initial build
        Joys::SSG.build(@content_dir, @output_dir)
        
        # Incremental build with unrelated change
        changed_files = ['/some/other/file.txt']
        result = Joys::SSG.build_incremental(@content_dir, changed_files, @output_dir)
        
        assert_equal [], result
      end
    end

    class TestEdgeCases < Minitest::Test
      def setup
        @temp_dir = Dir.mktmpdir
        @content_dir = File.join(@temp_dir, 'content')
        @output_dir = File.join(@temp_dir, 'dist')
        Joys::SSG.output_dir = @output_dir
        
        # Clear Joys registry - use correct variable names
        Joys.instance_variable_set(:@templates, {}) if Joys.instance_variable_defined?(:@templates)
        Joys.instance_variable_set(:@layouts, {}) if Joys.instance_variable_defined?(:@layouts)
        Joys.instance_variable_set(:@cache, {}) if Joys.instance_variable_defined?(:@cache)
      end

      def teardown
        FileUtils.rm_rf(@temp_dir)
        Joys.instance_variable_set(:@templates, {}) if Joys.instance_variable_defined?(:@templates)
        Joys.instance_variable_set(:@layouts, {}) if Joys.instance_variable_defined?(:@layouts)
        Joys.instance_variable_set(:@cache, {}) if Joys.instance_variable_defined?(:@cache)
      end

      def test_empty_content_directory
        FileUtils.mkdir_p(@content_dir)
        
        built_files = Joys::SSG.build(@content_dir, @output_dir)
        
        assert_equal 0, built_files.size
        assert Dir.exist?(@output_dir)
      end

      def test_nonexistent_content_directory
        built_files = Joys::SSG.build('/nonexistent/path', @output_dir)
        
        assert_equal 0, built_files.size
      end

      def test_special_characters_in_filenames
        FileUtils.mkdir_p(File.join(@content_dir, 'default'))
        
        # Files with special characters should be cleaned
        File.write(File.join(@content_dir, 'default/special-chars!@#.rb'), %{
          Joys.html { h1 "Special" }
        })

        built_files = Joys::SSG.build(@content_dir, @output_dir)
        
        # Should clean the special characters in the output path
        assert_equal 1, built_files.size
        assert built_files.first.match?(/special-chars/)
      end

      def test_deeply_nested_structure
        deep_path = File.join(@content_dir, 'default/very/deeply/nested/page')
        FileUtils.mkdir_p(File.dirname(deep_path))
        
        File.write("#{deep_path}.rb", %{
          Joys.html { h1 "Deep Page" }
        })

        built_files = Joys::SSG.build(@content_dir, @output_dir)
        
        assert_equal 1, built_files.size
        expected_path = 'very/deeply/nested/page/index.html'
        assert_includes built_files, expected_path
        assert File.exist?(File.join(@output_dir, expected_path))
      end
    end

    class TestGlobalMethod < Minitest::Test
      def test_build_static_site_method
        # Mock the SSG.build method to avoid file operations
        original_method = Joys::SSG.method(:build)
        
        Joys::SSG.define_singleton_method(:build) do |content_dir, output_dir, **options|
          { content_dir: content_dir, output_dir: output_dir, options: options }
        end

        result = Joys.build_static_site('/content', '/output', force: true)
        
        expected = { content_dir: '/content', output_dir: '/output', options: { force: true } }
        assert_equal expected, result

        # Restore original method
        Joys::SSG.define_singleton_method(:build, original_method)
      end
    end
  end
end
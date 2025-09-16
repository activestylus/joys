require 'minitest/autorun'
require 'minitest/pride'
require 'tmpdir'
require 'fileutils'
require 'json'
require_relative '../lib/joys/ssg'

# Mock Joys module for testing
module Joys
  module Data
    class Page
      attr_reader :items, :current_page, :total_pages, :total_items
      
      def initialize(items, current_page, total_pages, total_items)
        @items = items
        @current_page = current_page
        @total_pages = total_pages
        @total_items = total_items
      end
    end
  end

  def self.html(&block)
    block.call if block
  end

  def self.layout(name, &block)
    "<layout name='#{name}'>#{block.call if block}</layout>"
  end

  def self.comp(name, *args)
    "<component name='#{name}' args='#{args.join(', ')}'></component>"
  end
end

module Joys
  module SSG
    class TestSSG < Minitest::Test
      def setup
        @temp_dir = Dir.mktmpdir
        @content_dir = File.join(@temp_dir, 'content')
        @output_dir = File.join(@temp_dir, 'dist')
        @original_output_dir = Joys::SSG.output_dir
        Joys::SSG.output_dir = @output_dir
      end

      def teardown
        FileUtils.rm_rf(@temp_dir)
        Joys::SSG.output_dir = @original_output_dir
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
        
        # Create a simple page
        File.write(File.join(@content_dir, 'default/index.rb'), %{
          html { "<h1>Hello World</h1>" }
        })

        # Create a layout
        File.write(File.join(@content_dir, 'default/_layouts/main.rb'), %{
          # Layout content
        })

        built_files = Joys::SSG.build(@content_dir, @output_dir)

        assert_equal 1, built_files.size
        assert_includes built_files, 'index.html'
        assert File.exist?(File.join(@output_dir, 'index.html'))
        
        content = File.read(File.join(@output_dir, 'index.html'))
        assert_includes content, 'Hello World'
      end

      def test_multiple_domains
        create_test_structure
        
        # Create pages in different domains
        File.write(File.join(@content_dir, 'default/index.rb'), %{
          html { "<h1>Default Domain</h1>" }
        })
        
        File.write(File.join(@content_dir, 'blog/posts.rb'), %{
          html { "<h1>Blog Posts</h1>" }
        })

        built_files = Joys::SSG.build(@content_dir, @output_dir)

        assert_equal 2, built_files.size
        assert File.exist?(File.join(@output_dir, 'index.html'))
        assert File.exist?(File.join(@output_dir, 'blog/posts/index.html'))
      end

      def test_nested_pages
        create_test_structure
        
        FileUtils.mkdir_p(File.join(@content_dir, 'default/nested'))
        File.write(File.join(@content_dir, 'default/nested/page.rb'), %{
          html { "<h1>Nested Page</h1>" }
        })

        built_files = Joys::SSG.build(@content_dir, @output_dir)

        assert_includes built_files, 'nested/page/index.html'
        assert File.exist?(File.join(@output_dir, 'nested/page/index.html'))
      end

      def test_components_and_layouts_loading
        create_test_structure
        
        # Create component and layout files
        File.write(File.join(@content_dir, 'default/_components/header.rb'), %{
          # Header component
        })
        
        File.write(File.join(@content_dir, 'default/_layouts/main.rb'), %{
          # Main layout  
        })

        # Create page that uses them
        File.write(File.join(@content_dir, 'default/index.rb'), %{
          layout(:main) do
            comp(:header)
            html { "<h1>Content</h1>" }
          end
        })

        built_files = Joys::SSG.build(@content_dir, @output_dir)
        
        assert_equal 1, built_files.size
        content = File.read(File.join(@output_dir, 'index.html'))
        assert_includes content, "layout name='main'"
        assert_includes content, "component name='header'"
      end

      def test_asset_copying
        create_test_structure
        
        # Create public assets
        FileUtils.mkdir_p(File.join(@temp_dir, 'public/css'))
        File.write(File.join(@temp_dir, 'public/style.css'), 'body { color: blue; }')
        File.write(File.join(@temp_dir, 'public/css/main.css'), 'h1 { color: red; }')

        # Create page
        File.write(File.join(@content_dir, 'default/index.rb'), %{
          html { "<h1>Test</h1>" }
        })

        # Change to temp dir for asset copying to work
        Dir.chdir(@temp_dir) do
          Joys::SSG.build(@content_dir, @output_dir)
        end

        assert File.exist?(File.join(@output_dir, 'style.css'))
        assert File.exist?(File.join(@output_dir, 'css/main.css'))
        assert_equal 'body { color: blue; }', File.read(File.join(@output_dir, 'style.css'))
      end

      def test_dependency_tracking
        create_test_structure
        
        File.write(File.join(@content_dir, 'default/index.rb'), %{
          layout(:main) do
            comp(:header, 'test')
            html { "<h1>Test</h1>" }
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
          html { "<h1>Original</h1>" }
        })

        # First build
        Joys::SSG.build(@content_dir, @output_dir)
        original_content = File.read(File.join(@output_dir, 'index.html'))

        # Modify and rebuild without force
        File.write(File.join(@content_dir, 'default/index.rb'), %{
          html { "<h1>Modified</h1>" }
        })

        Joys::SSG.build(@content_dir, @output_dir, force: true)
        new_content = File.read(File.join(@output_dir, 'index.html'))

        refute_equal original_content, new_content
        assert_includes new_content, 'Modified'
      end

      def test_error_handling
        create_test_structure
        
        # Create page with syntax error
        File.write(File.join(@content_dir, 'default/broken.rb'), %{
          html { "<h1>Test</h1>
          # Missing closing brace
          }
        })

        # Should not raise exception, but should skip the broken page
        built_files = Joys::SSG.build(@content_dir, @output_dir)
        
        assert_equal 0, built_files.size
        refute File.exist?(File.join(@output_dir, 'broken/index.html'))
      end

      def test_skip_special_files
        create_test_structure
        
        # Create files that should be skipped
        File.write(File.join(@content_dir, 'default/_components/header.rb'), '# Component')
        File.write(File.join(@content_dir, 'default/_layouts/main.rb'), '# Layout')  
        File.write(File.join(@content_dir, 'default/data_helper.rb'), '# Data helper')
        
        # Create normal page
        File.write(File.join(@content_dir, 'default/index.rb'), %{
          html { "<h1>Index</h1>" }
        })

        built_files = Joys::SSG.build(@content_dir, @output_dir)

        # Should only build the index page
        assert_equal 1, built_files.size
        assert_includes built_files, 'index.html'
      end
    end

    class TestPageContext < Minitest::Test
      def setup
        @temp_file = File.join(Dir.tmpdir, 'test_page.rb')
        @context = PageContext.new(@temp_file)
      end

      def teardown
        File.delete(@temp_file) if File.exist?(@temp_file)
      end

      def test_dependency_tracking
        @context.layout(:main)
        @context.comp(:header)
        @context.comp(:footer, 'arg1', 'arg2')

        assert_includes @context.used_dependencies['layouts'], 'main'
        assert_includes @context.used_dependencies['components'], 'header' 
        assert_includes @context.used_dependencies['components'], 'footer'
      end

      def test_html_method
        result = @context.html { "<div>Content</div>" }
        assert_equal "<div>Content</div>", result
      end

      def test_layout_method
        result = @context.layout(:main) { "<h1>Content</h1>" }
        assert_includes result, "layout name='main'"
        assert_includes result, "<h1>Content</h1>"
      end

      def test_comp_method
        result = @context.comp(:header, 'title', class: 'main')
        assert_includes result, "component name='header'"
        assert_includes result, 'title'
      end

      def test_params_and_session
        assert_equal({}, @context.params)
        assert_equal({}, @context.session)
      end

      def test_hash_dependency_tracking
        # This would normally interact with Joys::Hash
        @context.hash(:posts)
        
        assert_includes @context.used_dependencies['hash'], 'posts'
      end

      def test_pagination_setup
        page_info = { url_path: '/blog/', output_path: 'blog/index.html' }
        @context.setup_pagination_capture(page_info)
        
        assert @context.instance_variable_get(:@capturing_pagination)
        assert_equal page_info, @context.instance_variable_get(:@base_page)
      end

      def test_paginate_with_collection
        items = (1..15).to_a
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

    class TestMockHashQuery < Minitest::Test
      def test_method_missing_returns_self
        query = MockHashQuery.new
        
        assert_equal query, query.where(id: 1)
        assert_equal query, query.order(:name)
        assert_equal query, query.limit(10)
      end

      def test_terminal_methods
        query = MockHashQuery.new
        
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

    class TestIncrementalBuild < Minitest::Test
      def setup
        @temp_dir = Dir.mktmpdir
        @content_dir = File.join(@temp_dir, 'content')
        @output_dir = File.join(@temp_dir, 'dist')
        create_test_structure
        Joys::SSG.output_dir = @output_dir
      end

      def teardown
        FileUtils.rm_rf(@temp_dir)
      end

      def create_test_structure
        FileUtils.mkdir_p(File.join(@content_dir, 'default'))
        FileUtils.mkdir_p(File.join(@content_dir, 'default/_components'))
        FileUtils.mkdir_p(File.join(@content_dir, 'default/_layouts'))
      end

      def test_incremental_build_with_no_changes
        File.write(File.join(@content_dir, 'default/index.rb'), %{
          html { "<h1>Test</h1>" }
        })

        # Initial build
        Joys::SSG.build(@content_dir, @output_dir)
        
        # Incremental build with unrelated change
        changed_files = ['/some/other/file.txt']
        result = Joys::SSG.build_incremental(@content_dir, changed_files, @output_dir)
        
        assert_equal [], result
      end

      def test_incremental_build_with_page_change
        page_file = File.join(@content_dir, 'default/index.rb')
        File.write(page_file, %{
          html { "<h1>Original</h1>" }
        })

        # Initial build
        Joys::SSG.build(@content_dir, @output_dir)
        
        # Modify page
        File.write(page_file, %{
          html { "<h1>Modified</h1>" }
        })

        # Incremental build
        result = Joys::SSG.build_incremental(@content_dir, [page_file], @output_dir)
        
        assert_includes result, 'index.html'
        content = File.read(File.join(@output_dir, 'index.html'))
        assert_includes content, 'Modified'
      end

      def test_incremental_build_with_component_change
        # Create component and page that uses it
        comp_file = File.join(@content_dir, 'default/_components/header.rb')
        File.write(comp_file, '# Header component')
        
        File.write(File.join(@content_dir, 'default/index.rb'), %{
          comp(:header)
          html { "<h1>Test</h1>" }
        })

        # Initial build 
        Joys::SSG.build(@content_dir, @output_dir)
        
        # Incremental build when component changes
        result = Joys::SSG.build_incremental(@content_dir, [comp_file], @output_dir)
        
        # Should rebuild pages that use the component
        assert_includes result, 'index.html'
      end

      def test_find_affected_pages
        # Set up some dependencies
        page_file = File.join(@content_dir, 'default/index.rb')
        Joys::SSG.instance_variable_set(:@dependencies, {
          'templates' => {
            page_file => {
              'components' => ['header'],
              'layouts' => ['main']
            }
          },
          'data' => {
            'posts' => [page_file]
          }
        })

        ssg = Class.new { extend Joys::SSG }
        
        # Test component change
        changed_files = [File.join(@content_dir, 'default/_components/header.rb')]
        affected = ssg.send(:find_affected_pages, changed_files)
        
        assert_equal 1, affected.size
        assert_equal page_file, affected.first[:file_path]

        # Test data change  
        changed_files = [File.join(@temp_dir, 'hash/posts_hash.rb')]
        affected = ssg.send(:find_affected_pages, changed_files)
        
        assert_equal 1, affected.size
        assert_equal page_file, affected.first[:file_path]

        # Test direct page change
        changed_files = [page_file]
        affected = ssg.send(:find_affected_pages, changed_files)
        
        assert_equal 1, affected.size
        assert_equal page_file, affected.first[:file_path]
      end
    end

    class TestPaginatedPages < Minitest::Test
      def setup
        @temp_dir = Dir.mktmpdir
        @content_dir = File.join(@temp_dir, 'content')
        @output_dir = File.join(@temp_dir, 'dist')
        create_test_structure
        Joys::SSG.output_dir = @output_dir
      end

      def teardown
        FileUtils.rm_rf(@temp_dir)
      end

      def create_test_structure
        FileUtils.mkdir_p(File.join(@content_dir, 'default'))
      end

      def test_paginated_page_generation
        # Create a page with pagination
        File.write(File.join(@content_dir, 'default/blog.rb'), %{
          posts = (1..25).map { |i| { id: i, title: "Post \#{i}" } }
          
          paginate(posts, per_page: 10) do |page|
            html do
              "<h1>Blog - Page \#{page.current_page}</h1>" +
              "<p>Posts: \#{page.items.map { |p| p[:title] }.join(', ')}</p>" +
              "<p>Page \#{page.current_page} of \#{page.total_pages}</p>"
            end
          end
        })

        built_files = Joys::SSG.build(@content_dir, @output_dir)

        # Should generate 3 pages (25 posts / 10 per page = 3 pages)
        expected_files = [
          'blog/index.html',
          'blog/page-2/index.html', 
          'blog/page-3/index.html'
        ]

        expected_files.each do |file|
          assert_includes built_files, file
          assert File.exist?(File.join(@output_dir, file))
        end

        # Check content of first page
        first_page = File.read(File.join(@output_dir, 'blog/index.html'))
        assert_includes first_page, 'Blog - Page 1'
        assert_includes first_page, 'Page 1 of 3'

        # Check content of second page
        second_page = File.read(File.join(@output_dir, 'blog/page-2/index.html'))
        assert_includes second_page, 'Blog - Page 2' 
        assert_includes second_page, 'Page 2 of 3'
      end

      def test_non_paginated_page
        File.write(File.join(@content_dir, 'default/about.rb'), %{
          html { "<h1>About Us</h1>" }
        })

        built_files = Joys::SSG.build(@content_dir, @output_dir)

        assert_equal 1, built_files.size
        assert_includes built_files, 'about/index.html'
        assert File.exist?(File.join(@output_dir, 'about/index.html'))
      end

      def test_empty_pagination
        File.write(File.join(@content_dir, 'default/empty.rb'), %{
          paginate([], per_page: 5) do |page|
            html { "<h1>No content</h1>" }
          end
        })

        built_files = Joys::SSG.build(@content_dir, @output_dir)

        assert_equal 1, built_files.size
        assert_includes built_files, 'empty/index.html'
      end
    end

    class TestEdgeCases < Minitest::Test
      def setup
        @temp_dir = Dir.mktmpdir
        @content_dir = File.join(@temp_dir, 'content')
        @output_dir = File.join(@temp_dir, 'dist')
        Joys::SSG.output_dir = @output_dir
      end

      def teardown
        FileUtils.rm_rf(@temp_dir)
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
          html { "<h1>Special</h1>" }
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
          html { "<h1>Deep Page</h1>" }
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
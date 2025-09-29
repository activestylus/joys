#!/usr/bin/env ruby
# frozen_string_literal: true
# bin/joys - CLI for Joys static site generator

require 'optparse'
require 'fileutils'
require 'json'

module Joys
  class CLI
    VERSION = "1.0.0"
    
    def initialize(args)
      @args = args
      @options = {}
    end
    
    def run
      case @args.first
      when 'new', 'n'
        run_new
      when 'build', 'b'
        run_build
      when 'serve', 's', 'dev'
        run_serve
      when 'version', '-v', '--version'
        puts VERSION
      when 'help', '-h', '--help', nil
        show_help
      else
        puts "Unknown command: #{@args.first}"
        show_help
        exit 1
      end
    rescue Interrupt
      puts "\nCancelled."
      exit 1
    rescue => e
      puts "Error: #{e.message}"
      puts "  #{e.backtrace.first}" if ENV['DEBUG']
      exit 1
    end
    
    private
    
    def run_new
      project_name = @args[1]
      
      unless project_name
        puts "Error: Project name required"
        puts "Usage: joys new PROJECT_NAME [options]"
        exit 1
      end
      
      parse_new_options
      
      # Prevent overwriting existing directories
      if Dir.exist?(project_name)
        puts "Error: Directory '#{project_name}' already exists"
        exit 1
      end
      
      generator = ProjectGenerator.new(project_name, @options)
      generator.generate!
      
      puts ""
      puts "✨ Project '#{project_name}' created successfully!"
      puts ""
      puts "Next steps:"
      puts "  cd #{project_name}"
      puts "  gem install joys"
      puts "  joys build"
      puts "  joys serve"
      puts ""
      
      if @options[:github_pages]
        puts "GitHub Pages setup:"
        puts "  1. Create a new GitHub repository"
        puts "  2. git init && git add . && git commit -m 'Initial commit'"
        puts "  3. git remote add origin <your-repo-url>"
        puts "  4. git push -u origin main"
        puts "  5. Enable GitHub Pages in repository settings"
        puts ""
      end
    end
    
    def run_build
      parse_build_options
      
      content_dir = @options[:content] || 'content'
      output_dir = @options[:output] || 'dist'
      
      unless Dir.exist?(content_dir)
        puts "Error: Content directory '#{content_dir}' not found"
        exit 1
      end
      
      require_relative '../lib/joys/ssg'
      
      start_time = Time.now
      built_files = Joys::SSG.build(content_dir, output_dir, force: @options[:force])
      elapsed = Time.now - start_time
      
      puts ""
      puts "✅ Built #{built_files.size} pages in #{elapsed.round(2)}s"
      puts "📁 Output: #{output_dir}/"
    end
    
    def run_serve
      parse_serve_options
      
      content_dir = @options[:content] || 'content'
      output_dir = @options[:output] || 'dist'
      port = @options[:port] || 5000
      
      unless Dir.exist?(content_dir)
        puts "Error: Content directory '#{content_dir}' not found"
        puts "Run 'joys new PROJECT_NAME' to create a new project"
        exit 1
      end
      
      require_relative '../lib/joys/dev_server'
      
      puts "Starting Joys development server..."
      puts "Press Ctrl+C to stop"
      puts ""
      
      Joys::SSGDev.start(content_dir, output_dir, port: port)
    end
    
    def parse_new_options
      OptionParser.new do |opts|
        opts.banner = "Usage: joys new PROJECT_NAME [options]"
        
        opts.on("--type=TYPE", ["blog", "docs", "portfolio", "basic"], 
                "Project type (blog, docs, portfolio, basic)") do |type|
          @options[:type] = type
        end
        
        opts.on("--domains=DOMAINS", Array, "Domains for multi-site setup") do |domains|
          @options[:domains] = domains
        end
        
        opts.on("--github-pages", "Setup GitHub Pages deployment") do
          @options[:github_pages] = true
        end
        
        opts.on("-h", "--help", "Show help") do
          puts opts
          exit
        end
      end.parse!(@args[2..-1] || [])
    end
    
    def parse_build_options
      OptionParser.new do |opts|
        opts.banner = "Usage: joys build [options]"
        
        opts.on("-c", "--content=DIR", "Content directory (default: content)") do |dir|
          @options[:content] = dir
        end
        
        opts.on("-o", "--output=DIR", "Output directory (default: dist)") do |dir|
          @options[:output] = dir
        end
        
        opts.on("-f", "--force", "Force rebuild (clear output directory)") do
          @options[:force] = true
        end
        
        opts.on("-h", "--help", "Show help") do
          puts opts
          exit
        end
      end.parse!(@args[1..-1] || [])
    end
    
    def parse_serve_options
      OptionParser.new do |opts|
        opts.banner = "Usage: joys serve [options]"
        
        opts.on("-c", "--content=DIR", "Content directory (default: content)") do |dir|
          @options[:content] = dir
        end
        
        opts.on("-o", "--output=DIR", "Output directory (default: dist)") do |dir|
          @options[:output] = dir
        end
        
        opts.on("-p", "--port=PORT", Integer, "Port (default: 5000)") do |port|
          @options[:port] = port
        end
        
        opts.on("-h", "--help", "Show help") do
          puts opts
          exit
        end
      end.parse!(@args[1..-1] || [])
    end
    
    def show_help
      puts <<~HELP
        Joys Static Site Generator v#{VERSION}
        
        USAGE:
            joys COMMAND [options]
        
        COMMANDS:
            new, n          Generate a new Joys project
            build, b        Build the static site
            serve, s, dev   Start development server
            version         Show version
            help            Show this help
        
        EXAMPLES:
            joys new my-blog --type=blog --github-pages
            joys new my-site --domains blog_site_com docs_site_com
            joys build --force
            joys serve --port=3000
        
        For more help on a command:
            joys COMMAND --help
      HELP
    end
  end
  
  class ProjectGenerator
    VALID_TYPES = %w[blog docs portfolio basic].freeze
    
    def initialize(project_name, options)
      @project_name = project_name
      @options = options
      @type = @options[:type] || prompt_for_type
      @domains = @options[:domains] || ['default']
      @github_pages = @options[:github_pages] || false
      
      # GitHub Pages only works with default domain
      if @github_pages && @domains != ['default']
        puts "Warning: GitHub Pages setup only supports single domain. Using 'default' domain."
        @domains = ['default']
      end
    end
    
    def generate!
      create_directory_structure
      generate_core_files
      generate_content_files
      generate_sample_data
      generate_github_pages_setup if @github_pages
      
      puts "📁 Generated #{@project_name}/ with #{@type} template"
      puts "🌍 Domains: #{@domains.join(', ')}" if @domains != ['default']
      puts "🚀 GitHub Pages: Ready" if @github_pages
    end
    
    private
    
    def prompt_for_type
      puts "What type of site are you building?"
      puts "  1. Blog (posts, categories, pagination)"
      puts "  2. Documentation (guides, API docs, navigation)"
      puts "  3. Portfolio (projects, gallery, contact)"
      puts "  4. Basic (minimal setup)"
      print "Choice [1-4]: "
      
      choice = STDIN.gets.chomp
      case choice
      when '1' then 'blog'
      when '2' then 'docs'
      when '3' then 'portfolio'
      when '4' then 'basic'
      else
        puts "Invalid choice. Using 'basic'."
        'basic'
      end
    end
    
    def create_directory_structure
      FileUtils.mkdir_p(@project_name)
      Dir.chdir(@project_name) do
        # Core directories
        FileUtils.mkdir_p(['data', 'public'])
        
        # Domain-specific content directories
        @domains.each do |domain|
          FileUtils.mkdir_p([
            "content/#{domain}",
            "content/#{domain}/assets",
            "content/_components",
            "content/_layouts"
          ])
        end
        
        # GitHub Pages specific
        FileUtils.mkdir_p('.github/workflows') if @github_pages
      end
    end
    
    def generate_core_files
      Dir.chdir(@project_name) do
        # Gemfile
        File.write('Gemfile', gemfile_content)
        
        # Build script
        File.write('build.rb', build_script_content)
        File.chmod(0755, 'build.rb')
        
        # README
        File.write('README.md', readme_content)
        
        # .gitignore
        File.write('.gitignore', gitignore_content)
        
        # Basic public assets
        File.write('public/favicon.ico', '')
        File.write('public/robots.txt', robots_txt_content)
      end
    end
    
    def generate_content_files
      Dir.chdir(@project_name) do
        generate_layouts
        generate_components
        
        @domains.each do |domain|
          generate_domain_pages(domain)
          generate_domain_assets(domain)
        end
        
        generate_error_pages
      end
    end
    
    def generate_layouts
      # Main layout
      File.write('content/_layouts/main.rb', main_layout_content)
      
      # Type-specific layouts
      case @type
      when 'blog'
        File.write('content/_layouts/post.rb', post_layout_content)
      when 'docs'
        File.write('content/_layouts/docs.rb', docs_layout_content)
      when 'portfolio'
        File.write('content/_layouts/project.rb', project_layout_content)
      end
    end
    
    def generate_components
      # Header component
      File.write('content/_components/header.rb', header_component_content)
      
      # Footer component  
      File.write('content/_components/footer.rb', footer_component_content)
      
      # Type-specific components
      case @type
      when 'blog'
        File.write('content/_components/post_card.rb', post_card_component_content)
      when 'docs'
        File.write('content/_components/doc_nav.rb', doc_nav_component_content)
      when 'portfolio'
        File.write('content/_components/project_card.rb', project_card_component_content)
      end
    end
    
    def generate_domain_pages(domain)
      case @type
      when 'blog'
        generate_blog_pages(domain)
      when 'docs'
        generate_docs_pages(domain)
      when 'portfolio'
        generate_portfolio_pages(domain)
      else
        generate_basic_pages(domain)
      end
    end
    
    def generate_blog_pages(domain)
      # Homepage
      File.write("content/#{domain}/index.rb", blog_homepage_content)
      
      # Blog listing
      FileUtils.mkdir_p("content/#{domain}/blog")
      File.write("content/#{domain}/blog/index.rb", blog_listing_content)
      
      # Individual post template
      File.write("content/#{domain}/blog/post.rb", blog_post_content)
      
      # About page
      File.write("content/#{domain}/about.rb", about_page_content)
    end
    
    def generate_docs_pages(domain)
      # Homepage
      File.write("content/#{domain}/index.rb", docs_homepage_content)
      
      # Getting started
      File.write("content/#{domain}/getting-started.rb", getting_started_content)
      
      # API reference
      FileUtils.mkdir_p("content/#{domain}/api")
      File.write("content/#{domain}/api/index.rb", api_index_content)
    end
    
    def generate_portfolio_pages(domain)
      # Homepage
      File.write("content/#{domain}/index.rb", portfolio_homepage_content)
      
      # Projects
      FileUtils.mkdir_p("content/#{domain}/projects")
      File.write("content/#{domain}/projects/index.rb", projects_listing_content)
      
      # About
      File.write("content/#{domain}/about.rb", portfolio_about_content)
      
      # Contact
      File.write("content/#{domain}/contact.rb", contact_page_content)
    end
    
    def generate_basic_pages(domain)
      # Homepage
      File.write("content/#{domain}/index.rb", basic_homepage_content)
      
      # About page
      File.write("content/#{domain}/about.rb", basic_about_content)
    end
    
    def generate_domain_assets(domain)
      File.write("content/#{domain}/assets/style.css", css_content)
    end
    
    def generate_error_pages
      @domains.each do |domain|
        File.write("content/#{domain}/404.rb", error_404_content)
        File.write("content/#{domain}/500.rb", error_500_content)
      end
    end
    
    def generate_sample_data
      case @type
      when 'blog'
        File.write('data/posts_data.rb', blog_data_content)
        File.write('data/config_data.rb', config_data_content)
      when 'docs'
        File.write('data/docs_data.rb', docs_data_content)
        File.write('data/config_data.rb', config_data_content)
      when 'portfolio'
        File.write('data/projects_data.rb', portfolio_data_content)
        File.write('data/config_data.rb', config_data_content)
      else
        File.write('data/config_data.rb', basic_config_data_content)
      end
    end
    
    def generate_github_pages_setup
      # GitHub Actions workflow
      File.write('.github/workflows/deploy.yml', github_actions_content)
      
      # GitHub Pages build script (simpler version of build.rb)
      File.write('build.rb', github_build_script_content)
    end
    
    # Content generation methods follow...
    def gemfile_content
      <<~GEMFILE
        source 'https://rubygems.org'
        
        gem 'joys'
      GEMFILE
    end
    
    def build_script_content
      <<~RUBY
        #!/usr/bin/env ruby
        require 'joys'
        
        puts "🔨 Building #{@type} site..."
        start_time = Time.now
        
        built_files = Joys.build_static_site('content', 'dist')
        elapsed = Time.now - start_time
        
        puts "✅ Built \#{built_files.size} pages in \#{elapsed.round(2)}s"
        puts "📁 Output: dist/"
        puts ""
        puts "To preview: joys serve"
      RUBY
    end
    
    def github_build_script_content
      <<~RUBY
        #!/usr/bin/env ruby
        require 'joys'
        
        puts "🔨 Building for GitHub Pages..."
        built_files = Joys.build_static_site('content', 'dist')
        puts "✅ Built \#{built_files.size} pages"
      RUBY
    end
    
    def readme_content
      site_title = @project_name.tr('_-', ' ').split.map(&:capitalize).join(' ')
      
      <<~MARKDOWN
        # #{site_title}
        
        A #{@type} site built with [Joys](https://github.com/fractaledmind/joys) static site generator.
        
        ## Development
        
        ```bash
        # Install dependencies
        gem install joys
        
        # Build the site
        joys build
        
        # Start development server with live reload
        joys serve
        ```
        
        ## Structure
        
        - `content/` - Page templates and content
        - `data/` - Data files  
        - `public/` - Static assets
        - `dist/` - Generated site (created by build)
        
        #{github_pages_readme_section if @github_pages}
        ## Customization
        
        - Edit `content/_layouts/` for page layouts
        - Edit `content/_components/` for reusable components
        - Edit `data/` files for site data
        - Add assets to `content/[domain]/assets/` or `public/`
        
        ## Deployment
        
        The `dist/` directory contains the built site. Deploy it to any static hosting service.
      MARKDOWN
    end
    
    def github_pages_readme_section
      <<~MARKDOWN
        ## GitHub Pages Deployment
        
        This project is configured for GitHub Pages deployment:
        
        1. Push to the `main` branch
        2. GitHub Actions will automatically build and deploy
        3. Site will be available at `https://YOUR_USERNAME.github.io/#{@project_name}`
        
        The deployment workflow is in `.github/workflows/deploy.yml`.
        
      MARKDOWN
    end
    
    def gitignore_content
      <<~GITIGNORE
        dist/
        .DS_Store
        *.log
        .env
      GITIGNORE
    end
    
    def robots_txt_content
      <<~TXT
        User-agent: *
        Allow: /
      TXT
    end
    
    def main_layout_content
      <<~RUBY
        Joys.define :layout, :main do
          doctype
          html(lang: "en") {
            head {
              meta(charset: "utf-8")
              meta(name: "viewport", content: "width=device-width, initial-scale=1")
              title { pull(:title) }
              link(rel: "stylesheet", href: "/style.css")
              link(rel: "icon", href: "/favicon.ico")
            }
            body {
              comp(:header)
              main(cs: "container") {
                pull(:content)
              }
              comp(:footer)
            }
          }
        end
      RUBY
    end
    
    def post_layout_content
      <<~RUBY
        Joys.define :layout, :post do
          layout(:main) {
            push(:title) { "\#{@post[:title]} - \#{data(:config).site_title}" }
            push(:content) {
              article(cs: "post") {
                header {
                  h1(@post[:title])
                  time(@post[:published_at].strftime("%B %d, %Y"))
                }
                div(cs: "content") {
                  raw @post[:content]
                }
              }
            }
          }
        end
      RUBY
    end
    
    def docs_layout_content
      <<~RUBY
        Joys.define :layout, :docs do
          layout(:main) {
            push(:title) { "\#{@doc[:title]} - \#{data(:config).site_title}" }
            push(:content) {
              div(cs: "docs-layout") {
                aside(cs: "sidebar") {
                  comp(:doc_nav)
                }
                article(cs: "doc-content") {
                  header {
                    h1(@doc[:title])
                  }
                  div(cs: "content") {
                    raw @doc[:content]
                  }
                }
              }
            }
          }
        end
      RUBY
    end
    
    def project_layout_content
      <<~RUBY
        Joys.define :layout, :project do
          layout(:main) {
            push(:title) { "\#{@project[:title]} - \#{data(:config).site_title}" }
            push(:content) {
              article(cs: "project") {
                header {
                  h1(@project[:title])
                  p(@project[:description])
                }
                div(cs: "project-content") {
                  raw @project[:content]
                }
                footer(cs: "project-meta") {
                  if @project[:github_url]
                    a("View on GitHub", href: @project[:github_url], target: "_blank")
                  end
                  if @project[:demo_url]
                    a("Live Demo", href: @project[:demo_url], target: "_blank")
                  end
                }
              }
            }
          }
        end
      RUBY
    end
    
    def header_component_content
      <<~RUBY
        Joys.define :comp, :header do
          header(cs: "site-header") {
            div(cs: "container") {
              a(data(:config).site_title, href: "/", cs: "logo")
              nav {
                a("Home", href: "/")
                #{navigation_links}
              }
            }
          }
        end
      RUBY
    end
    
    def navigation_links
      case @type
      when 'blog'
        'a("Blog", href: "/blog/")
                a("About", href: "/about/")'
      when 'docs'
        'a("Documentation", href: "/getting-started/")
                a("API", href: "/api/")'
      when 'portfolio'
        'a("Projects", href: "/projects/")
                a("About", href: "/about/")
                a("Contact", href: "/contact/")'
      else
        'a("About", href: "/about/")'
      end
    end
    
    def footer_component_content
      <<~RUBY
        Joys.define :comp, :footer do
          footer(cs: "site-footer") {
            div(cs: "container") {
              p {
                txt "© \#{Date.current.year} \#{data(:config).site_title}. "
                txt "Built with "
                a("Joys", href: "https://github.com/fractaledmind/joys", target: "_blank")
                txt "."
              }
            }
          }
        end
      RUBY
    end
    
    def post_card_component_content
      <<~RUBY
        Joys.define :comp, :post_card do |post|
          article(cs: "post-card") {
            h3 {
              a(post[:title], href: "/blog/\#{post[:slug]}/")
            }
            time(post[:published_at].strftime("%B %d, %Y"))
            p(post[:excerpt])
            a("Read more →", href: "/blog/\#{post[:slug]}/", cs: "read-more")
          }
        end
      RUBY
    end
    
    def doc_nav_component_content
      <<~RUBY
        Joys.define :comp, :doc_nav do
          nav(cs: "doc-nav") {
            h3 "Documentation"
            ul {
              data(:docs).each do |doc|
                li {
                  a(doc[:title], href: "/\#{doc[:slug]}/")
                }
              end
            }
          }
        end
      RUBY
    end
    
    def project_card_component_content
      <<~RUBY
        Joys.define :comp, :project_card do |project|
          article(cs: "project-card") {
            h3 {
              a(project[:title], href: "/projects/\#{project[:slug]}/")
            }
            p(project[:description])
            div(cs: "project-meta") {
              if project[:tech]
                project[:tech].each do |tech|
                  span(tech, cs: "tech-tag")
                end
              end
            }
          }
        end
      RUBY
    end
    
    def blog_homepage_content
      <<~RUBY
        recent_posts = data(:posts).recent(3)
        site_config = data(:config)
        
        Joys.html do
          layout(:main) {
            push(:title) { site_config.site_title }
            push(:content) {
              section(cs: "hero") {
                h1(site_config.site_title)
                p(site_config.description)
                a("Read the Blog →", href: "/blog/", cs: "btn btn-primary")
              }
              
              if recent_posts.any?
                section(cs: "recent-posts") {
                  h2 "Recent Posts"
                  div(cs: "posts-grid") {
                    recent_posts.each do |post|
                      comp(:post_card, post)
                    end
                  }
                  a("View All Posts →", href: "/blog/", cs: "btn btn-secondary")
                }
              end
            }
          }
        end
      RUBY
    end
    
    def blog_listing_content
      <<~RUBY
        site_config = data(:config)
        
        Joys.html do
          layout(:main) {
            push(:title) { "Blog - \#{site_config.site_title}" }
            push(:content) {
              h1 "Blog"
              
              paginate(data(:posts).published, per_page: 5) do |page|
                div(cs: "posts-list") {
                  page.items.each do |post|
                    comp(:post_card, post)
                  end
                }
                
                if page.total_pages > 1
                  nav(cs: "pagination") {
                    if page.prev_page
                      a("← Previous", href: page.prev_page == 1 ? "/blog/" : "/blog/page-\#{page.prev_page}/")
                    end
                    
                    span "Page \#{page.current_page} of \#{page.total_pages}"
                    
                    if page.next_page
                      a("Next →", href: "/blog/page-\#{page.next_page}/")
                    end
                  }
                end
              end
            }
          }
        end
      RUBY
    end
    
    def blog_post_content
      <<~RUBY
        # This would typically get the post slug from URL params in a real app
        # For static generation, you'd need to generate individual post pages
        post = data(:posts).find_by(slug: params[:slug]) || data(:posts).first
        
        Joys.html do
          layout(:post) {
            # Content is handled by the post layout
          }
        end
      RUBY
    end
    
    def about_page_content
      <<~RUBY
        site_config = data(:config)
        
        Joys.html do
          layout(:main) {
            push(:title) { "About - \#{site_config.site_title}" }
            push(:content) {
              article {
                h1 "About"
                p "This is the about page for \#{site_config.site_title}."
                p "Edit this page in content/default/about.rb"
              }
            }
          }
        end
      RUBY
    end
    
    def docs_homepage_content
      <<~RUBY
        site_config = data(:config)
        recent_docs = data(:docs).limit(3)
        
        Joys.html do
          layout(:main) {
            push(:title) { site_config.site_title }
            push(:content) {
              section(cs: "hero") {
                h1(site_config.site_title)
                p(site_config.description)
                a("Get Started →", href: "/getting-started/", cs: "btn btn-primary")
              }
              
              if recent_docs.any?
                section(cs: "recent-docs") {
                  h2 "Documentation"
                  div(cs: "docs-grid") {
                    recent_docs.each do |doc|
                      article(cs: "doc-card") {
                        h3 {
                          a(doc[:title], href: "/\#{doc[:slug]}/")
                        }
                        p(doc[:description])
                      }
                    end
                  }
                }
              end
            }
          }
        end
      RUBY
    end
    
    def getting_started_content
      <<~RUBY
        site_config = data(:config)
        
        Joys.html do
          layout(:main) {
            push(:title) { "Getting Started - \#{site_config.site_title}" }
            push(:content) {
              article {
                h1 "Getting Started"
                p "Welcome to the documentation!"
                
                h2 "Installation"
                pre {
                  code "gem install joys"
                }
                
                h2 "Quick Start"
                p "Get up and running in minutes:"
                ol {
                  li "Clone this repository"
                  li "Run `joys build`"
                  li "Open `dist/index.html` in your browser"
                }
                
                p "Edit content in the `content/` directory to customize your site."
              }
            }
          }
        end
      RUBY
    end
    
    def api_index_content
      <<~RUBY
        site_config = data(:config)
        
        Joys.html do
          layout(:main) {
            push(:title) { "API Reference - \#{site_config.site_title}" }
            push(:content) {
              article {
                h1 "API Reference"
                p "Complete API documentation for your project."
                
                h2 "Endpoints"
                p "Coming soon - add your API documentation here."
              }
            }
          }
        end
      RUBY
    end
    
    def portfolio_homepage_content
      <<~RUBY
        site_config = data(:config)
        featured_projects = data(:projects).featured.limit(3)
        
        Joys.html do
          layout(:main) {
            push(:title) { site_config.site_title }
            push(:content) {
              section(cs: "hero") {
                h1(site_config.site_title)
                p(site_config.description)
                a("View My Work →", href: "/projects/", cs: "btn btn-primary")
              }
              
              if featured_projects.any?
                section(cs: "featured-projects") {
                  h2 "Featured Projects"
                  div(cs: "projects-grid") {
                    featured_projects.each do |project|
                      comp(:project_card, project)
                    end
                  }
                  a("View All Projects →", href: "/projects/", cs: "btn btn-secondary")
                }
              end
            }
          }
        end
      RUBY
    end
    
    def projects_listing_content
      <<~RUBY
        site_config = data(:config)
        
        Joys.html do
          layout(:main) {
            push(:title) { "Projects - \#{site_config.site_title}" }
            push(:content) {
              h1 "Projects"
              
              div(cs: "projects-grid") {
                data(:projects).each do |project|
                  comp(:project_card, project)
                end
              }
            }
          }
        end
      RUBY
    end
    
    def portfolio_about_content
      <<~RUBY
        site_config = data(:config)
        
        Joys.html do
          layout(:main) {
            push(:title) { "About - \#{site_config.site_title}" }
            push(:content) {
              article {
                h1 "About Me"
                p "I'm a developer who loves building things."
                p "Check out my projects and get in touch!"
              }
            }
          }
        end
      RUBY
    end
    
    def contact_page_content
      <<~RUBY
        site_config = data(:config)
        
        Joys.html do
          layout(:main) {
            push(:title) { "Contact - \#{site_config.site_title}" }
            push(:content) {
              article {
                h1 "Contact"
                p "Get in touch!"
                
                ul {
                  li { a("Email: hello@example.com", href: "mailto:hello@example.com") }
                  li { a("GitHub", href: "https://github.com/yourusername", target: "_blank") }
                  li { a("Twitter", href: "https://twitter.com/yourusername", target: "_blank") }
                }
              }
            }
          }
        end
      RUBY
    end
    
    def basic_homepage_content
      <<~RUBY
        site_config = data(:config)
        
        Joys.html do
          layout(:main) {
            push(:title) { site_config.site_title }
            push(:content) {
              article {
                h1(site_config.site_title)
                p "Welcome to your new Joys site!"
                p "Edit this page in content/default/index.rb to get started."
              }
            }
          }
        end
      RUBY
    end
    
    def basic_about_content
      <<~RUBY
        site_config = data(:config)
        
        Joys.html do
          layout(:main) {
            push(:title) { "About - \#{site_config.site_title}" }
            push(:content) {
              article {
                h1 "About"
                p "This is the about page."
                p "Edit content/default/about.rb to customize it."
              }
            }
          }
        end
      RUBY
    end
    
    def error_404_content
      <<~RUBY
        site_config = data(:config)
        
        Joys.html do
          layout(:main) {
            push(:title) { "Page Not Found - \#{site_config.site_title}" }
            push(:content) {
              article(cs: "error-page") {
                h1 "Page Not Found"
                p "The page you're looking for doesn't exist."
                a("← Back to Home", href: "/", cs: "btn btn-primary")
              }
            }
          }
        end
      RUBY
    end
    
    def error_500_content
      <<~RUBY
        site_config = data(:config)
        
        Joys.html do
          layout(:main) {
            push(:title) { "Server Error - \#{site_config.site_title}" }
            push(:content) {
              article(cs: "error-page") {
                h1 "Server Error"
                p "Something went wrong while building this page."
                a("← Back to Home", href: "/", cs: "btn btn-primary")
              }
            }
          }
        end
      RUBY
    end
    
    def css_content
      <<~CSS
        /* Basic styles for #{@project_name} */
        
        * {
          margin: 0;
          padding: 0;
          box-sizing: border-box;
        }
        
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          line-height: 1.6;
          color: #333;
        }
        
        .container {
          max-width: 1200px;
          margin: 0 auto;
          padding: 0 2rem;
        }
        
        .site-header {
          background: #fff;
          border-bottom: 1px solid #eee;
          padding: 1rem 0;
        }
        
        .site-header .container {
          display: flex;
          justify-content: space-between;
          align-items: center;
        }
        
        .logo {
          font-size: 1.5rem;
          font-weight: 600;
          text-decoration: none;
          color: #333;
        }
        
        nav a {
          margin-left: 2rem;
          text-decoration: none;
          color: #666;
        }
        
        nav a:hover {
          color: #333;
        }
        
        main {
          padding: 2rem 0;
          min-height: calc(100vh - 200px);
        }
        
        .hero {
          text-align: center;
          padding: 4rem 0;
          background: #f8f9fa;
          margin: -2rem -2rem 2rem -2rem;
        }
        
        .hero h1 {
          font-size: 3rem;
          margin-bottom: 1rem;
        }
        
        .hero p {
          font-size: 1.2rem;
          color: #666;
          margin-bottom: 2rem;
        }
        
        .btn {
          display: inline-block;
          padding: 0.75rem 1.5rem;
          text-decoration: none;
          border-radius: 4px;
          font-weight: 500;
        }
        
        .btn-primary {
          background: #007bff;
          color: white;
        }
        
        .btn-secondary {
          background: #6c757d;
          color: white;
        }
        
        .btn:hover {
          opacity: 0.9;
        }
        
        .site-footer {
          background: #f8f9fa;
          padding: 2rem 0;
          margin-top: 4rem;
          border-top: 1px solid #eee;
          text-align: center;
          color: #666;
        }
        
        #{type_specific_css}
      CSS
    end
    
    def type_specific_css
      case @type
      when 'blog'
        <<~CSS
        
        .posts-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
          gap: 2rem;
          margin: 2rem 0;
        }
        
        .post-card {
          border: 1px solid #eee;
          border-radius: 8px;
          padding: 1.5rem;
          background: #fff;
        }
        
        .post-card h3 {
          margin-bottom: 0.5rem;
        }
        
        .post-card time {
          color: #666;
          font-size: 0.9rem;
        }
        
        .post-card p {
          margin: 1rem 0;
        }
        
        .read-more {
          color: #007bff;
          text-decoration: none;
          font-weight: 500;
        }
        CSS
      when 'portfolio'
        <<~CSS
        
        .projects-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
          gap: 2rem;
          margin: 2rem 0;
        }
        
        .project-card {
          border: 1px solid #eee;
          border-radius: 8px;
          padding: 1.5rem;
          background: #fff;
        }
        
        .tech-tag {
          display: inline-block;
          background: #e9ecef;
          color: #495057;
          padding: 0.25rem 0.5rem;
          border-radius: 3px;
          font-size: 0.8rem;
          margin-right: 0.5rem;
          margin-bottom: 0.5rem;
        }
        CSS
      else
        ""
      end
    end
    
    def blog_data_content
      <<~RUBY
        Joys::Data.define :posts do
          from_array([
            {
              title: "Welcome to Your New Blog",
              slug: "welcome",
              excerpt: "This is your first post. Edit hash/posts_hash.rb to add more content.",
              content: "<p>Welcome to your new blog built with Joys!</p><p>This is your first post. You can edit this content in <code>hash/posts_hash.rb</code> or replace this file-based approach with your preferred data source.</p><p>Joys makes it easy to create fast, beautiful static sites with Ruby.</p>",
              published_at: Date.current,
              featured: true,
              published: true
            },
            {
              title: "Getting Started with Joys",
              slug: "getting-started",
              excerpt: "Learn the basics of building sites with Joys static site generator.",
              content: "<p>Joys is a powerful static site generator built for Ruby developers.</p><h2>Key Features</h2><ul><li>Ruby-based templates</li><li>Component system</li><li>Asset pipeline with hashing</li><li>Live reload development server</li></ul>",
              published_at: Date.current - 1,
              featured: false,
              published: true
            },
            {
              title: "Customizing Your Site",
              slug: "customizing",
              excerpt: "How to customize layouts, components, and styling in your Joys site.",
              content: "<p>Customizing your Joys site is straightforward:</p><h2>Layouts</h2><p>Edit files in <code>content/_layouts/</code> to change page structure.</p><h2>Components</h2><p>Create reusable components in <code>content/_components/</code>.</p><h2>Styling</h2><p>Add CSS to <code>content/default/assets/style.css</code> or use individual component styles.</p>",
              published_at: Date.current - 7,
              featured: false,
              published: true
            }
          ])
          
          scope({
            recent: ->(n=5) { order(:published_at, desc: true).limit(n) },
            featured: -> { where(featured: true) },
            published: -> { where(published: true) }
          })
        end
      RUBY
    end
    
    def docs_data_content
      <<~RUBY
        Joys::Data.define :docs do
          from_array([
            {
              title: "Getting Started",
              slug: "getting-started",
              description: "Learn the basics of using this project",
              content: "<p>Welcome to the documentation!</p><p>This is a sample documentation site built with Joys.</p>",
              order: 1
            },
            {
              title: "API Reference",
              slug: "api",
              description: "Complete API documentation",
              content: "<p>API documentation goes here.</p>",
              order: 2
            },
            {
              title: "Examples",
              slug: "examples", 
              description: "Code examples and tutorials",
              content: "<p>Examples and tutorials will be added here.</p>",
              order: 3
            }
          ])
          
          scope({
            ordered: -> { order(:order) }
          })
        end
      RUBY
    end
    
    def portfolio_data_content
      <<~RUBY
        Joys::Data.define :projects do
          from_array([
            {
              title: "My Awesome App",
              slug: "awesome-app",
              description: "A web application built with modern technologies",
              content: "<p>This is a detailed description of my awesome app.</p><h2>Features</h2><ul><li>Feature 1</li><li>Feature 2</li><li>Feature 3</li></ul>",
              tech: ["Ruby", "Rails", "JavaScript"],
              github_url: "https://github.com/yourusername/awesome-app",
              demo_url: "https://awesome-app.example.com",
              featured: true
            },
            {
              title: "Cool Library", 
              slug: "cool-library",
              description: "An open source library for developers",
              content: "<p>A useful library that solves common problems.</p>",
              tech: ["Ruby", "Gem"],
              github_url: "https://github.com/yourusername/cool-library",
              demo_url: nil,
              featured: true
            },
            {
              title: "Static Site",
              slug: "static-site",
              description: "A beautiful static site built with Joys",
              content: "<p>This portfolio site itself, built with Joys!</p>",
              tech: ["Ruby", "Joys", "CSS"],
              github_url: "https://github.com/yourusername/portfolio",
              demo_url: nil,
              featured: false
            }
          ])
          
          scope({
            featured: -> { where(featured: true) },
            by_tech: ->(tech) { where(tech: { contains: tech }) }
          })
        end
      RUBY
    end
    
    def config_data_content
      title = @project_name.tr('_-', ' ').split.map(&:capitalize).join(' ')
      
      <<~RUBY
        Joys::Data.define :config do
          from_array([{
            site_title: "#{title}",
            description: "#{description_for_type}",
            author: "Your Name",
            url: "https://#{@github_pages ? 'yourusername.github.io/' + @project_name : 'example.com'}"
          }])
          
          def method_missing(method, *args)
            data = first
            data[method] if data&.key?(method)
          end
        end
      RUBY
    end
    
    def basic_config_data_content
      title = @project_name.tr('_-', ' ').split.map(&:capitalize).join(' ')
      
      <<~RUBY
        Joys::Data.define :config do
          from_array([{
            site_title: "#{title}",
            description: "A site built with Joys",
            author: "Your Name"
          }])
          
          def method_missing(method, *args)
            data = first
            data[method] if data&.key?(method)
          end
        end
      RUBY
    end
    
    def description_for_type
      case @type
      when 'blog'
        "A blog built with Joys static site generator"
      when 'docs'
        "Documentation site built with Joys"
      when 'portfolio'
        "Portfolio site showcasing my work"
      else
        "A site built with Joys"
      end
    end
    
    def github_actions_content
      <<~YAML
        name: Build and Deploy to GitHub Pages
        
        on:
          push:
            branches: [ main ]
          pull_request:
            branches: [ main ]
        
        permissions:
          contents: read
          pages: write
          id-token: write
        
        concurrency:
          group: "pages"
          cancel-in-progress: false
        
        jobs:
          build:
            runs-on: ubuntu-latest
            steps:
            - name: Checkout
              uses: actions/checkout@v4
              
            - name: Setup Ruby
              uses: ruby/setup-ruby@v1
              with:
                ruby-version: '3.3'
                bundler-cache: true
                
            - name: Setup Pages
              uses: actions/configure-pages@v4
              
            - name: Build site
              run: ruby build.rb
              
            - name: Upload artifact
              uses: actions/upload-pages-artifact@v3
              with:
                path: ./dist
        
          deploy:
            environment:
              name: github-pages
              url: \\${{ steps.deployment.outputs.page_url }}
            runs-on: ubuntu-latest
            needs: build
            steps:
            - name: Deploy to GitHub Pages
              id: deployment
              uses: actions/deploy-pages@v4
      YAML
    end
  end
end

# Run CLI if called directly
if __FILE__ == $0
  Joys::CLI.new(ARGV).run
end
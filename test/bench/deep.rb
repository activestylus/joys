require_relative '../../lib/joys'
require 'memory_profiler'
require 'benchmark'
require 'memory_profiler'
require 'erb'
require 'phlex'
require 'slim'
SAMPLE_USERS = [
  { name: "Alice Johnson", avatar: "/avatars/alice.jpg", bio: "Full-stack Ruby developer passionate about clean code", posts: 127, followers: 2847 },
  { name: "Bob Chen", avatar: "/avatars/bob.jpg", bio: "DevOps engineer and Kubernetes enthusiast", posts: 89, followers: 1492 },
  { name: "Carol Martinez", avatar: "/avatars/carol.jpg", bio: "Frontend developer specializing in React and TypeScript", posts: 203, followers: 3721 },
  { name: "David Kim", avatar: "/avatars/david.jpg", bio: "Product manager with a technical background", posts: 56, followers: 891 },
  { name: "Emma Wilson", avatar: "/avatars/emma.jpg", bio: "UX designer who codes", posts: 78, followers: 1337 }
]
NAV_ITEMS = [
  { text: "Dashboard", url: "/dashboard", icon: "📊" },
  { text: "Users", url: "/users", icon: "👥" },
  { text: "Projects", url: "/projects", icon: "📁" },
  { text: "Analytics", url: "/analytics", icon: "📈" },
  { text: "Settings", url: "/settings", icon: "⚙️" }
]
Joys.define(:comp,:user_card) do |user|
  styles(scoped:true) do
    css ".nav { display: flex; justify-content: space-between; }.nav .logo, .nav .menu { align-items: center; }"
    media_max "768px", ".nav { flex-direction: column; }"
    media_min "769px", ".nav .menu { display: flex; gap: 2rem; }"
  end
  div(cs:"user-card bg-white rounded-lg shadow-md p-6 mb-4") {
    div(cs:"flex items-center mb-4") {
      img(src: user[:avatar], alt: user[:name], cs: "avatar w-16 h-16 rounded-full mr-4")
      div {
        h3(user[:name], cs: "text-xl font-semibold text-gray-800")
        p("#{user[:posts]} posts • #{user[:followers]} followers", cs: "text-gray-600 text-sm")
      }
    }
    if user[:bio] then p(user[:bio], cs: "bio text-gray-700 leading-relaxed") end
    div(cs:"flex space-x-2 mt-4") {
      comp(:button,"Follow", size: "sm")
      button("Message", cs: "btn btn-secondary btn-sm")
    }
  }
end
Joys.define(:comp,:nav_item) do |i, active = false|
  li(cs:"nav-item") {
    cs = "nav-link flex items-center px-4 py-2 text-sm rounded-md transition-colors #{active ? 'bg-blue-100 text-blue-700' : 'text-gray-600 hover:bg-gray-100'}"
    a(href: i[:url], cs: cs) {
      span(i[:icon], cs: "mr-3")
      txt(i[:text])
    }
  }
end
Joys.define(:comp,:button) do |text, type: "primary", size: "md", **attrs|
  classes = "btn btn-#{type} btn-#{size} px-4 py-2 rounded-md font-medium transition-colors focus:outline-none focus:ring-2"
  case type
  when "primary"
    classes += " bg-blue-600 text-white hover:bg-blue-700 focus:ring-blue-500"
  when "secondary"  
    classes += " bg-gray-200 text-gray-800 hover:bg-gray-300 focus:ring-gray-400"
  when "success"
    classes += " bg-green-600 text-white hover:bg-green-700 focus:ring-green-500"
  end
  button(text, cs: classes, **attrs)
end
Joys.define(:comp,:stats_widget) do |title, value, icon|
  div(cs:"stats-widget bg-white rounded-lg shadow p-6") {
    div(cs:"flex items-center justify-between") {
      div {
        p(title, cs: "text-sm text-gray-600 mb-1")
        p(value, cs: "text-2xl font-bold text-gray-900")
      }
      div(cs:"text-3xl") { txt(icon) }
    }
  }
end
Joys.define(:layout, :main) do
  doctype
  html(lang: "en") {
    head {
      meta(charset: "utf-8")
      meta(name: "viewport", content: "width=device-width, initial-scale=1")
      title { pull(:title) }
      link(href: "https://cdn.tailwindcss.com", rel: "stylesheet")
      pull_styles
    }
    body(cs:"bg-gray-50 min-h-screen") {
      div(cs:"flex h-screen") {
        div(cs:"w-64 bg-white shadow-lg") {
          div(cs:"p-6") {
            h1(cs:"text-xl font-bold text-gray-800") { pull(:app_name) }
          }
          nav(cs:"mt-6") {
            pull(:navigation)
          }
        }
        div(cs:"flex-1 flex flex-col overflow-hidden") {
          header(cs: "bg-white shadow-sm border-b") {
            div(cs:"px-6 py-4") {
              pull(:header)
            }
          }
          main(cs: "flex-1 overflow-auto") {
            div(cs:"p-6") {
              pull(:main)
            }
          }
        }
      }
      footer(cs:"bg-gray-800 text-white py-4") {
        div(cs:"container mx-auto px-6 text-center") {
          pull(:footer)
        }
      }
      pull(:scripts)
    }
  }
end
Joys.define(:page, :home) do
  layout(:main) {
    push(:title) { txt("Team Dashboard - Joys Framework") }
    push(:app_name) { txt("Joys Dashboard") }
    push(:navigation) {
      ul(cs:"space-y-2") {
        NAV_ITEMS.each_with_index { |item, index|
          active = index == 0  # First item active
          comp(:nav_item, item, active)
        }
      }
    }
    push(:header) {
      div(cs:"flex justify-between items-center") {
        div {
          h2("Team Overview", cs:"text-2xl font-bold text-gray-900")
          p("Manage your team and track performance", cs: "text-gray-600 mt-1")
        }
        div(cs:"flex space-x-3") {
          comp(:button,"Add User", type: "primary")
          comp(:button,"Export Data", type: "secondary")
        }
      }
    }
    push(:main) {
      # Stats row
      div(cs:"grid grid-cols-1 md:grid-cols-3 gap-6 mb-8") {
        comp(:stats_widget,"Total Users", "1,247", "👥")
        comp(:stats_widget,"Active Projects", "89", "📁")  
        comp(:stats_widget,"This Month", "+15.3%", "📈")
      }
      
      # Main content area
      div(cs:"grid grid-cols-1 lg:grid-cols-2 gap-8") {
        div {
          h3("Team Members", cs:"text-lg font-semibold mb-4")
          div(cs:"space-y-4") {
            SAMPLE_USERS.each_with_index do |user, i|
              comp :user_card, user
            end
          }
        }
        
        div {
          h3("Quick Actions", cs: "text-lg font-semibold mb-4")
          div(cs:"bg-white rounded-lg shadow p-6") {
            div(cs:"space-y-4") {
              div(cs:"flex justify-between items-center py-3 border-b") {
                span("Send team update")
                comp(:button,"Send", size: "sm")
              }
              div(cs:"flex justify-between items-center py-3 border-b") {
                span("Schedule team meeting") 
                comp(:button,"Schedule", type: "secondary", size: "sm")
              }
              div(cs:"flex justify-between items-center py-3 border-b") {
                span("Review pending requests")
                comp(:button,"Review", type: "success", size: "sm")
              }
              div(cs:"flex justify-between items-center py-3") {
                span("Generate team report")
                comp(:button,"Generate", size: "sm")
              }
            }
          }
        }
      }
    }
    
    push(:footer) {
      txt("© 2024 Joys Framework. Built with ❤️ and nuclear-powered components.")
    }
  }
end
class ERBRenderer
  def initialize
    @layout_template = ERB.new(erb_layout_template)
    @page_template = ERB.new(erb_page_template) 
    @user_card_template = ERB.new(erb_user_card_template)
    @nav_item_template = ERB.new(erb_nav_item_template)
    @button_template = ERB.new(erb_button_template)
    @stats_widget_template = ERB.new(erb_stats_widget_template)
  end
  def render_page
    @layout_template.result(binding)
  end
def erb_layout_template
  <<~ERB
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Team Dashboard - ERB Framework</title>
      <link href="https://cdn.tailwindcss.com" rel="stylesheet">
    </head>
    <body class="bg-gray-50 min-h-screen">
      <div class="flex h-screen">
        <!-- Sidebar -->
        <div class="w-64 bg-white shadow-lg">
          <div class="p-6">
            <h1 class="text-xl font-bold text-gray-800">ERB Dashboard</h1>
          </div>
          <nav class="mt-6">
            <%= render_navigation %>
          </nav>
        </div>
        <!-- Main content area -->
        <div class="flex-1 flex flex-col overflow-hidden">
          <!-- Header -->
          <header class="bg-white shadow-sm border-b">
            <div class="px-6 py-4">
              <%= render_header %>
            </div>
          </header>
          <!-- Main content -->
          <main class="flex-1 overflow-auto">
            <div class="p-6">
              <%= render_page_content %>
            </div>
          </main>
        </div>
      </div>
      <!-- Footer -->
      <footer class="bg-gray-800 text-white py-4">
        <div class="container mx-auto px-6 text-center">
          © 2024 ERB Framework. Traditional server-side rendering.
        </div>
      </footer>
    </body>
    </html>
  ERB
end
def render_page
  @layout_template.result(binding)  # This should render the full layout now
end
def render_page_content
  @page_template.result(binding)
end
  def erb_page_template
    <<~ERB
      <!-- Stats row -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
        <%= render_stats_widget("Total Users", "1,247", "👥") %>
        <%= render_stats_widget("Active Projects", "89", "📁") %>
        <%= render_stats_widget("This Month", "+15.3%", "📈") %>
      </div>
      <!-- Main content area -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
        <div>
          <h3 class="text-lg font-semibold mb-4">Team Members</h3>
          <div class="space-y-4">
            <% SAMPLE_USERS.each do |user| %>
              <%= render_user_card(user) %>
            <% end %>
          </div>
        </div>
        <div>
          <h3 class="text-lg font-semibold mb-4">Quick Actions</h3>
          <div class="bg-white rounded-lg shadow p-6">
            <div class="space-y-4">
              <div class="flex justify-between items-center py-3 border-b">
                <span>Send team update</span>
                <%= render_button("Send", size: "sm") %>
              </div>
              <div class="flex justify-between items-center py-3 border-b">
                <span>Schedule team meeting</span>
                <%= render_button("Schedule", type: "secondary", size: "sm") %>
              </div>
              <div class="flex justify-between items-center py-3 border-b">
                <span>Review pending requests</span>
                <%= render_button("Review", type: "success", size: "sm") %>
              </div>
              <div class="flex justify-between items-center py-3">
                <span>Generate team report</span>
                <%= render_button("Generate", size: "sm") %>
              </div>
            </div>
          </div>
        </div>
      </div>
    ERB
  end
  def render_navigation
    html = '<ul class="space-y-2">'
    NAV_ITEMS.each_with_index do |item, index|
      active = index == 0
      html += @nav_item_template.result_with_hash(item: item, active: active)
    end
    html += '</ul>'
    html
  end
  def render_header
    <<~HTML
      <div class="flex justify-between items-center">
        <div>
          <h2 class="text-2xl font-bold text-gray-900">Team Overview</h2>
          <p class="text-gray-600 mt-1">Manage your team and track performance</p>
        </div>
        <div class="flex space-x-3">
          #{render_button("Add User", type: "primary")}
          #{render_button("Export Data", type: "secondary")}
        </div>
      </div>
    HTML
  end
  def render_user_card(user)
    @user_card_template.result_with_hash(user: user)
  end
  def render_button(text, type: "primary", size: "md")
    # Create a binding with the variables
    button_text = text
    button_type = type  
    button_size = size
    @button_template.result(binding)
  end
  def render_stats_widget(title, value, icon)
    @stats_widget_template.result_with_hash(title: title, value: value, icon: icon)
  end
  def erb_user_card_template
    <<~ERB
      <div class="user-card bg-white rounded-lg shadow-md p-6 mb-4">
        <div class="flex items-center mb-4">
          <img src="<%= user[:avatar] %>" alt="<%= user[:name] %>" class="avatar w-16 h-16 rounded-full mr-4">
          <div>
            <h3 class="text-xl font-semibold text-gray-800"><%= user[:name] %></h3>
            <p class="text-gray-600 text-sm"><%= user[:posts] %> posts • <%= user[:followers] %> followers</p>
          </div>
        </div>
        <% if user[:bio] %>
          <p class="bio text-gray-700 leading-relaxed"><%= user[:bio] %></p>
        <% end %>
        <div class="flex space-x-2 mt-4">
          <button class="btn btn-primary btn-sm px-4 py-2 rounded-md font-medium bg-blue-600 text-white">Follow</button>
          <button class="btn btn-secondary btn-sm px-4 py-2 rounded-md font-medium bg-gray-200 text-gray-800">Message</button>
        </div>
      </div>
    ERB
  end
  def erb_nav_item_template
    <<~ERB
      <li class="nav-item">
        <a href="<%= item[:url] %>" class="flex items-center px-4 py-2 text-sm rounded-md transition-colors <%= active ? 'bg-blue-100 text-blue-700' : 'text-gray-600 hover:bg-gray-100' %>">
          <span class="mr-3"><%= item[:icon] %></span>
          <%= item[:text] %>
        </a>
      </li>
    ERB
  end
def erb_button_template
  <<~ERB
    <button class="btn btn-<%= button_type %> btn-<%= button_size %> px-4 py-2 rounded-md font-medium bg-blue-600 text-white"><%= button_text %></button>
  ERB
end
  def erb_stats_widget_template
    <<~ERB
      <div class="stats-widget bg-white rounded-lg shadow p-6">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-sm text-gray-600 mb-1"><%= title %></p>
            <p class="text-2xl font-bold text-gray-900"><%= value %></p>
          </div>
          <div class="text-3xl"><%= icon %></div>
        </div>
      </div>
    ERB
  end
end
class PhlexComponents
  class UserCard < Phlex::HTML
    def initialize(user);@user = user;end
    def view_template
      div(class: "user-card bg-white rounded-lg shadow-md p-6 mb-4") do
        div(class: "flex items-center mb-4") do
          img(src: @user[:avatar], alt: @user[:name], class: "avatar w-16 h-16 rounded-full mr-4")
          div do
            h3(class: "text-xl font-semibold text-gray-800") {@user[:name]}
            p(class: "text-gray-600 text-sm") {"#{@user[:posts]} posts • #{@user[:followers]} followers"}
          end
        end
        if @user[:bio]
          p(class: "bio text-gray-700 leading-relaxed") {@user[:bio]}
        end
        div(class: "flex space-x-2 mt-4") do
          button(class: "btn btn-primary btn-sm px-4 py-2 rounded-md font-medium bg-blue-600 text-white") {"Follow"}
          button(class: "btn btn-secondary btn-sm px-4 py-2 rounded-md font-medium bg-gray-200 text-gray-800") {"Message"}
        end
      end
    end
  end
  class NavItem < Phlex::HTML
    def initialize(item, active = false);@item = item;@active = active;end
    def view_template
      li(class: "nav-item") do
        a(href: @item[:url], class: nav_classes) do
          span(class: "mr-3") {@item[:icon]}
          @item[:text]
        end
      end
    end
    private
    def nav_classes
      base = "flex items-center px-4 py-2 text-sm rounded-md transition-colors"
      @active ? "#{base} bg-blue-100 text-blue-700" : "#{base} text-gray-600 hover:bg-gray-100"
    end
  end
  class Button < Phlex::HTML
    def initialize(text, type: "primary", size: "md")
      @text = text;@type = type;@size = size
    end
    def view_template;button(class: button_classes) {@text};end
    private
    def button_classes
      base = "btn btn-#{@type} btn-#{@size} px-4 py-2 rounded-md font-medium transition-colors focus:outline-none focus:ring-2"
      case @type
      when "primary"
        "#{base} bg-blue-600 text-white hover:bg-blue-700 focus:ring-blue-500"
      when "secondary"
        "#{base} bg-gray-200 text-gray-800 hover:bg-gray-300 focus:ring-gray-400"
      when "success"
        "#{base} bg-green-600 text-white hover:bg-green-700 focus:ring-green-500"
      end
    end
  end
  class StatsWidget < Phlex::HTML
    def initialize(title, value, icon)
      @title = title;@value = value  ;@icon = icon
    end
    def view_template
      div(class: "stats-widget bg-white rounded-lg shadow p-6") do
        div(class: "flex items-center justify-between") do
          div do
            p(class: "text-sm text-gray-600 mb-1") {@title}
            p(class: "text-2xl font-bold text-gray-900") {@value}
          end
          div(class: "text-3xl"){@icon}
        end
      end
    end
  end
end
class PhlexLayout < Phlex::HTML
  def view_template
    html(lang: "en") do
      head do
        meta(charset: "utf-8")
        meta(name: "viewport", content: "width=device-width, initial-scale=1")
        title {"Team Dashboard - Phlex Framework"}
        link(href: "https://cdn.tailwindcss.com", rel: "stylesheet")
      end
      body(class: "bg-gray-50 min-h-screen") do
        div(class: "flex h-screen") do
          # Sidebar
          div(class: "w-64 bg-white shadow-lg") do
            div(class: "p-6") do
              h1(class: "text-xl font-bold text-gray-800") {"Phlex Dashboard"}
            end
            nav(class: "mt-6") do
              ul(class: "space-y-2") do
                NAV_ITEMS.each_with_index do |item, index|
                  render PhlexComponents::NavItem.new(item, index == 0)
                end
              end
            end
          end
          # Main content area
          div(class: "flex-1 flex flex-col overflow-hidden") do
            # Header
            header(class: "bg-white shadow-sm border-b") do
              div(class: "px-6 py-4") do
                div(class: "flex justify-between items-center") do
                  div do
                    h2(class: "text-2xl font-bold text-gray-900") {"Team Overview"}
                    p(class: "text-gray-600 mt-1") {"Manage your team and track performance"}
                  end
                  div(class: "flex space-x-3") do
                    render PhlexComponents::Button.new("Add User", type: "primary")
                    render PhlexComponents::Button.new("Export Data", type: "secondary")
                  end
                end
              end
            end
            main(class: "flex-1 overflow-auto") do
              div(class: "p-6") do
                # Stats row
                div(class: "grid grid-cols-1 md:grid-cols-3 gap-6 mb-8") do
                  render PhlexComponents::StatsWidget.new("Total Users", "1,247", "👥")
                  render PhlexComponents::StatsWidget.new("Active Projects", "89", "📁")
                  render PhlexComponents::StatsWidget.new("This Month", "+15.3%", "📈")
                end
                div(class: "grid grid-cols-1 lg:grid-cols-2 gap-8") do
                  div do
                    h3(class: "text-lg font-semibold mb-4") {"Team Members"}
                    div(class: "space-y-4") do
                      SAMPLE_USERS.each do |user|
                        render PhlexComponents::UserCard.new(user)
                      end
                    end
                  end
                  div do
                    h3(class: "text-lg font-semibold mb-4") {"Quick Actions"}
                    div(class: "bg-white rounded-lg shadow p-6") do
                      div(class: "space-y-4") do
                        div(class: "flex justify-between items-center py-3 border-b") do
                          span {"Send team update"}
                          render PhlexComponents::Button.new("Send", size: "sm")
                        end
                        div(class: "flex justify-between items-center py-3 border-b") do
                          span {"Schedule team meeting"}
                          render PhlexComponents::Button.new("Schedule", type: "secondary", size: "sm")
                        end
                        div(class: "flex justify-between items-center py-3 border-b") do
                          span {"Review pending requests"}
                          render PhlexComponents::Button.new("Review", type: "success", size: "sm")
                        end
                        div(class: "flex justify-between items-center py-3") do
                          span {"Generate team report"}
                          render PhlexComponents::Button.new("Generate", size: "sm")
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
        footer(class: "bg-gray-800 text-white py-4") do
          div(class: "container mx-auto px-6 text-center") do
            "© 2024 Phlex Framework. Ruby components for the modern web."
          end
        end
      end
    end
  end
end
def render_phlex_page
  PhlexLayout.new.call
end
class SlimRenderer
  def initialize
    @layout_template = Slim::Template.new { slim_layout_template }
    @user_card_template = Slim::Template.new { slim_user_card_template }
    @nav_item_template = Slim::Template.new { slim_nav_item_template }
    @button_template = Slim::Template.new { slim_button_template }
    @stats_widget_template = Slim::Template.new { slim_stats_widget_template }
  end
  def render_page
    @layout_template.render(self)
  end
  def render_user_card(user)
    @user_card_template.render(self, user: user)
  end
  def render_nav_item(item, active = false)
    @nav_item_template.render(self, item: item, active: active)
  end
  def render_button(text, type: "primary", size: "md")
    @button_template.render(self, text: text, type: type, size: size)
  end
  def render_stats_widget(title, value, icon)
    @stats_widget_template.render(self, title: title, value: value, icon: icon)
  end
  def button_classes(type, size)
    base = "btn btn-#{type} btn-#{size} px-4 py-2 rounded-md font-medium transition-colors focus:outline-none focus:ring-2"
    case type
    when "primary"
      "#{base} bg-blue-600 text-white hover:bg-blue-700 focus:ring-blue-500"
    when "secondary"
      "#{base} bg-gray-200 text-gray-800 hover:bg-gray-300 focus:ring-gray-400"
    when "success"
      "#{base} bg-green-600 text-white hover:bg-green-700 focus:ring-green-500"
    end
  end
  def nav_classes(active)
    base = "flex items-center px-4 py-2 text-sm rounded-md transition-colors"
    active ? "#{base} bg-blue-100 text-blue-700" : "#{base} text-gray-600 hover:bg-gray-100"
  end
  private
  def slim_layout_template
    <<~SLIM
      doctype html
      html lang="en"
        head
          meta charset="utf-8"
          meta name="viewport" content="width=device-width, initial-scale=1"
          title Team Dashboard - Slim Framework
          link href="https://cdn.tailwindcss.com" rel="stylesheet"
        body.bg-gray-50.min-h-screen
          .flex.h-screen
            / Sidebar
            .w-64.bg-white.shadow-lg
              .p-6
                h1.text-xl.font-bold.text-gray-800 Slim Dashboard
              nav.mt-6
                ul.space-y-2
                  - NAV_ITEMS.each_with_index do |item, index|
                    == render_nav_item(item, index == 0)
            / Main content area  
            .flex-1.flex.flex-col.overflow-hidden
              / Header
              header.bg-white.shadow-sm.border-b
                .px-6.py-4
                  .flex.justify-between.items-center
                    div
                      h2.text-2xl.font-bold.text-gray-900 Team Overview
                      p.text-gray-600.mt-1 Manage your team and track performance
                    .flex.space-x-3
                      == render_button("Add User", type: "primary")
                      == render_button("Export Data", type: "secondary")
              / Main content
              main.flex-1.overflow-auto
                .p-6
                  / Stats row
                  .grid.grid-cols-1.md:grid-cols-3.gap-6.mb-8
                    == render_stats_widget("Total Users", "1,247", "👥")
                    == render_stats_widget("Active Projects", "89", "📁")
                    == render_stats_widget("This Month", "+15.3%", "📈")
                  / Main content area
                  .grid.grid-cols-1.lg:grid-cols-2.gap-8
                    div
                      h3.text-lg.font-semibold.mb-4 Team Members
                      .space-y-4
                        - SAMPLE_USERS.each do |user|
                          == render_user_card(user)
                    div
                      h3.text-lg.font-semibold.mb-4 Quick Actions
                      .bg-white.rounded-lg.shadow.p-6
                        .space-y-4
                          .flex.justify-between.items-center.py-3.border-b
                            span Send team update
                            == render_button("Send", size: "sm")
                          .flex.justify-between.items-center.py-3.border-b
                            span Schedule team meeting
                            == render_button("Schedule", type: "secondary", size: "sm")
                          .flex.justify-between.items-center.py-3.border-b
                            span Review pending requests
                            == render_button("Review", type: "success", size: "sm")
                          .flex.justify-between.items-center.py-3
                            span Generate team report
                            == render_button("Generate", size: "sm")
          / Footer
          footer.bg-gray-800.text-white.py-4
            .container.mx-auto.px-6.text-center
              | © 2024 Slim Framework. Beautiful, minimalist templates.
    SLIM
  end
  def slim_user_card_template
    <<~SLIM
      .user-card.bg-white.rounded-lg.shadow-md.p-6.mb-4
        .flex.items-center.mb-4
          img.avatar.w-16.h-16.rounded-full.mr-4 src=user[:avatar] alt=user[:name]
          div
            h3.text-xl.font-semibold.text-gray-800 = user[:name]
            p.text-gray-600.text-sm = "\#{user[:posts]} posts • \#{user[:followers]} followers"
        - if user[:bio]
          p.bio.text-gray-700.leading-relaxed = user[:bio]
        .flex.space-x-2.mt-4
          button.btn.btn-primary.btn-sm.px-4.py-2.rounded-md.font-medium.bg-blue-600.text-white Follow
          button.btn.btn-secondary.btn-sm.px-4.py-2.rounded-md.font-medium.bg-gray-200.text-gray-800 Message
    SLIM
  end
  def slim_nav_item_template
    <<~SLIM
      li.nav-item
        a.nav-link href=item[:url] class=nav_classes(active)
          span.mr-3 = item[:icon]
          = item[:text]
    SLIM
  end
  def slim_button_template
    <<~SLIM
      button class=button_classes(type, size) = text
    SLIM
  end
  def slim_stats_widget_template
    <<~SLIM
      .stats-widget.bg-white.rounded-lg.shadow.p-6
        .flex.items-center.justify-between
          div
            p.text-sm.text-gray-600.mb-1 = title
            p.text-2xl.font-bold.text-gray-900 = value
          .text-3xl = icon
    SLIM
  end
end
def render_slim_page;SlimRenderer.new.render_page;end
ITERATIONS = 1000
puts "=== 🚀 ULTIMATE TEMPLATE SYSTEM SHOWDOWN 🚀 ===";puts
render_joys_page = Joys.page(:home)
erb_renderer = ERBRenderer.new
slim_renderer = SlimRenderer.new
puts "\n=== 🔥 HOT RENDER (cached objects) ==="
Benchmark.bm(7) do |x|
  x.report("JOYS:") {ITERATIONS.times { Joys.page_home }}
  x.report("SLIM:") {ITERATIONS.times { slim_renderer.render_page }}
  x.report("PHLEX:") {ITERATIONS.times { render_phlex_page }}
  x.report("ERB:") {ITERATIONS.times { erb_renderer.render_page }}
end
def cold_joys;Joys.page(:home) end
def cold_erb; ERBRenderer.new.render_page;end
def cold_phlex;PhlexLayout.new.call;end
def cold_slim;SlimRenderer.new.render_page;end
puts "\n=== ❄️ COLD RENDER (new object per call) ==="
Benchmark.bm(10) do |x|
  x.report("Joys (cold):") { ITERATIONS.times { cold_joys } }
  x.report("ERB  (cold):") { ITERATIONS.times { cold_erb } }
  x.report("Slim (cold):") { ITERATIONS.times { cold_slim } }
  x.report("Phlex(cold):") { ITERATIONS.times { cold_phlex } }
end
puts "\n=== MEMORY PROFILE ===";puts
report = MemoryProfiler.report do;100.times { Joys.page(:home) };end
puts "Joys memory: #{report.total_allocated_memsize} bytes"
report = MemoryProfiler.report do;100.times { SlimRenderer.new };end
puts "Slim memory: #{report.total_allocated_memsize} bytes"
report = MemoryProfiler.report do;100.times { PhlexLayout.new.call };end
puts "Phlex memory: #{report.total_allocated_memsize} bytes"
report = MemoryProfiler.report do;100.times { ERBRenderer.new };end
puts "ERB memory: #{report.total_allocated_memsize} bytes"


puts "\n=== TEMPLATE ENGINE VERIFICATION ===";puts
joys_result = render_joys_page
erb_result = ERBRenderer.new.render_page
phlex_result = render_phlex_page
slim_result = render_slim_page
puts "  JOYS:  #{joys_result.length} chars"
puts "  ERB:   #{erb_result.length} chars"
puts "  PHLEX: #{phlex_result.length} chars"
puts "  SLIM:  #{slim_result.length} chars"
# puts joys_result

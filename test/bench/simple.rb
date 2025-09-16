#!/usr/bin/env ruby
require_relative '../../lib/joys'
require 'benchmark'
require 'slim'
require 'phlex'
require 'memory_profiler'
puts "Ruby: #{RUBY_VERSION}"
puts "=" * 50

TEST_DATA = {
  title: "Performance Test",
  users: [
    { name: "Alice", email: "alice@test.com", active: true },
    { name: "Bob", email: "bob@test.com", active: false },
    { name: "Carol", email: "carol@test.com", active: true }
  ],
  stats: { total: 100, active: 75 }
}.freeze

module JoysBench
  @cache = {}
  @templates = {}
  
  def self.define(type, name, &template)
    @templates["#{type}_#{name}"] = template
  end
  
  def self.render_page(name, **locals)
    template = @templates["page_#{name}"]
    raise "No template: #{name}" unless template
    
    renderer = Object.new
    renderer.instance_eval do
      @bf = String.new(capacity: 1024)
      locals.each { |k, v| instance_variable_set("@#{k}", v) }
      
      def div(content = nil, cs: nil, &block)
        @bf << "<div"
        @bf << " class=\"#{cs}\"" if cs
        @bf << ">"
        if block
          instance_eval(&block)
        elsif content
          @bf << content.to_s
        end
        @bf << "</div>"
      end
      
      def h1(content); @bf << "<h1>#{content}</h1>"; end
      def h2(content); @bf << "<h2>#{content}</h2>"; end
      def p(content); @bf << "<p>#{content}</p>"; end
      def span(content); @bf << "<span>#{content}</span>"; end
    end
    
    renderer.instance_eval(&template)
    renderer.instance_variable_get(:@bf)
  end
end

# Register Joys template
JoysBench.define(:page, :test) do
  div(cs: "container") do
    h1(@title)
    div(cs: "stats") do
      p("Total: #{@stats[:total]}")
      p("Active: #{@stats[:active]}")
    end
    div(cs: "users") do
      @users.each do |user|
        div(cs: "user #{'active' if user[:active]}") do
          h2(user[:name])
          p(user[:email])
          span(user[:active] ? "Active" : "Inactive")
        end
      end
    end
  end
end

# === PHLEX IMPLEMENTATION ===
class PhlexTest < Phlex::HTML
  def initialize(title:, users:, stats:)
    @title = title
    @users = users  
    @stats = stats
  end
  
  def view_template
    div(class: "container") do
      h1 { @title }
      div(class: "stats") do
        p { "Total: #{@stats[:total]}" }
        p { "Active: #{@stats[:active]}" }
      end
      div(class: "users") do
        @users.each do |user|
          div(class: "user#{ ' active' if user[:active]}") do
            h2 { user[:name] }
            p { user[:email] }
            span { user[:active] ? "Active" : "Inactive" }
          end
        end
      end
    end
  end
end

def render_phlex(data)
  PhlexTest.new(**data).call
end

# === SLIM IMPLEMENTATION ===
SLIM_TEMPLATE = <<~SLIM
  .container
    h1 = title
    .stats
      p = "Total: \#{stats[:total]}"
      p = "Active: \#{stats[:active]}"
    .users
      - users.each do |user|
        .user class=('active' if user[:active])
          h2 = user[:name]
          p = user[:email]
          span = user[:active] ? "Active" : "Inactive"
SLIM

def render_slim(data)
  template = Slim::Template.new { SLIM_TEMPLATE }
  template.render(Object.new, data)
end

# === ERB IMPLEMENTATION ===
require 'erb'

ERB_TEMPLATE = <<~ERB
  <div class="container">
    <h1><%= title %></h1>
    <div class="stats">
      <p>Total: <%= stats[:total] %></p>
      <p>Active: <%= stats[:active] %></p>
    </div>
    <div class="users">
      <% users.each do |user| %>
        <div class="user<%= ' active' if user[:active] %>">
          <h2><%= user[:name] %></h2>
          <p><%= user[:email] %></p>
          <span><%= user[:active] ? "Active" : "Inactive" %></span>
        </div>
      <% end %>
    </div>
  </div>
ERB

def render_erb(data)
  ERB.new(ERB_TEMPLATE).result_with_hash(data)
end

# === VERIFICATION ===
puts "=== OUTPUT VERIFICATION ==="

joys_output = JoysBench.render_page(:test, **TEST_DATA)
slim_output = render_slim(TEST_DATA)
erb_output = render_erb(TEST_DATA)
phlex_compiled = proc { render_phlex(TEST_DATA) }
puts "Joys length: #{joys_output.length}"
puts "Slim length: #{slim_output.length}" 
puts "ERB length:  #{erb_output.length}"

# Quick visual check - first 200 chars
puts "\nJoys preview: #{joys_output[0..200]}..."
puts "\nSlim preview: #{slim_output[0..200]}..."
puts "\nERB preview:  #{erb_output[0..200]}..."

puts "\n=== ❄️ COLD RENDER (new object per call) ==="

ITERATIONS = 10_000

Benchmark.bm(10) do |x|
  # Test with identical call patterns - all create new objects
  x.report("Joys:") do
    ITERATIONS.times do
      JoysBench.render_page(:test, **TEST_DATA)
    end
  end
  
  x.report("Slim:") do
    template = Slim::Template.new { SLIM_TEMPLATE }
    ITERATIONS.times do
      template.render(Object.new, TEST_DATA)
    end
  end
  
  x.report("ERB:") do
    template = ERB.new(ERB_TEMPLATE)
    ITERATIONS.times do
      template.result_with_hash(TEST_DATA)
    end
  end
  x.report("Phlex:") do
    ITERATIONS.times {render_phlex(TEST_DATA) }
  end
end

puts "\n=== 🔥 HOT RENDER (cached objects) ==="

# Pre-compile templates
joys_compiled = proc { JoysBench.render_page(:test, **TEST_DATA) }
slim_compiled = Slim::Template.new { SLIM_TEMPLATE }
erb_compiled = ERB.new(ERB_TEMPLATE)

Benchmark.bm(10) do |x|
  x.report("Joys:") do
    ITERATIONS.times { joys_compiled.call }
  end
  
  x.report("Slim:") do
    ITERATIONS.times { slim_compiled.render(Object.new, TEST_DATA) }
  end
  
  x.report("ERB:") do
    ITERATIONS.times { erb_compiled.result_with_hash(TEST_DATA) }
  end
  x.report("Phlex:") do
    ITERATIONS.times { phlex_compiled.call }
  end
end

puts "\n=== MEMORY BENCHMARK ===\n"

report = MemoryProfiler.report do;100.times { JoysBench.render_page(:test, **TEST_DATA) };end
puts "Joys memory: #{report.total_allocated_memsize} bytes"
report = MemoryProfiler.report do;100.times { render_slim(TEST_DATA) };end
puts "Slim memory: #{report.total_allocated_memsize} bytes"
report = MemoryProfiler.report do;100.times { phlex_compiled = proc { render_phlex(TEST_DATA) } };end
puts "Phlex memory: #{report.total_allocated_memsize} bytes"
report = MemoryProfiler.report do;100.times { render_erb(TEST_DATA) };end
puts "ERB memory: #{report.total_allocated_memsize} bytes"
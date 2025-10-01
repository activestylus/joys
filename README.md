![joys](https://github.com/user-attachments/assets/ec594256-b1ee-4ec7-a876-491abcfa1d66)

# Joys - HTML Templates at the Speed of Light

**Write HTML like Ruby, render it at the speed of C.**

Joys is a pure-Ruby HTML templating engine with built-in CSS and ludicrous-speed rendering.

## Why Joys?

- **Blazing Fast** - 3x faster on cold render. Orders of magnitude faster after caching.
- **Pure Ruby** - No new syntax to learn. It's just methods and blocks.
- **Testable** - Components are just functions. Test them like any Ruby code.
- **Fully Integrated Styling** - Deduplicated, sorted css right inside your components
- **Framework Agnostic** - Use it in Rails, Roda, Sinatra, Hanami, Syro, etc.

---

## Installation

```ruby
gem 'joys'
```

## Quick Start: The Power of Joys DSL

```ruby
html = Joys.html do
  div(cs: "card") do
    h1 "Hello"
    p "World", cs: "text-sm"
    txt "It's me!"
  end
end

puts html

# => <div class="card"><h1>Hello</h1><p class="text-sm">World</p>It's me!</div>
```

### Security & HTML Escaping

Joys ships with sensible defaults to prevent XSS attacks.

All text nodes must be rendered explicitly via the `txt()` or `raw()` helpers

```ruby
# txt escapes HTML (safe by default)
p { txt user_input }  # "<script>alert('xss')</script>" becomes safe text

# raw outputs HTML (use with caution)
div { raw markdown_to_html(content) }

# raw shortcut is available for those who find it tedious
div { _ markdown_to_html(content) }

# Pass raw: true to any tag
div(content, raw: true)  # content renders as HTML
```
Following Ruby conventions, adding a bang `!` to the elemtn indicates a method with a more 'potent' or 'dangerous' effect—in this case, disabling HTML escaping.

```
# Escaped HTML
div("hello<br>world") # <div>Hello&lt;br&gt;world</div>

# Raw Unescaped HTML with bang (div!)
div!("hello<br>world") # <div>Hello<br>world</div>
```

### Smart Class Handling

Of course, you can use `class` attribute, but Joys provides `cs` for brevity given how often it is used.

You also get some extra benefits from `cs`:

```ruby
# String, Array, or conditional classes - all just work
div(cs: "card")
div(cs: ["card", "active"])
div(cs: ["card", user.premium? && "premium"])
div(cs: ["base", ("active" if active?)])
```

### Boolean Attributes That Don't Suck

Elegant handling with underscore-to-dash conversion and proper boolean semantics:

```ruby
input(type: "text", auto_focus: true, form_novalidate: true)
# => <input type="text" autofocus formnovalidate>

input(type: "text", disabled: false)
# => <input type="text">
```

Write attributes naturally with underscores - Joys outputs the correct HTML boolean names. Works automatically for all boolean attributes, including: `autofocus`, `autoplay`, `checked`, `controls`, `disabled`, `default`, `formnovalidate`, `hidden`, `inert`, `itemscope`, `loop`, `multiple`, `muted`, `novalidate`, `open`, `readonly`, `required`, `reversed`, `scoped`, `seamless` and `selected`.

### Smart Data and ARIA Attributes

Nested hashes auto-expand with underscore-to-dash conversion and intelligent false handling:

```ruby
button(
  "Save",
  cs: "btn", 
  data: {
    controller: "form_handler",
    user_id: 123,
    confirm_message: "Are you sure?"
  },
  aria: {
    label: "Save changes",
    expanded: false,        # Boolean false - omitted
    disabled: "false"       # String false - rendered
  }
)
# => <button class="btn" data-controller="form_handler" data-user-id="123" 
#     data-confirm-message="Are you sure?" aria-label="Save changes" 
#     aria-disabled="false">Save</button>
```

**Key behaviors:**
- Underscores convert to dashes: `user_id` → `data-user-id`
- Boolean `false` values get omitted entirely
- String `"false"` values render normally
- All other values render with proper escaping

### Every HTML Tag, Zero Boilerplate

```ruby
# All standard HTML tags just work
article {
  header { h1("Post Title") }
  section { p("Content...") }
  footer { time(datetime: "2024-01-01") { txt "Jan 1" } }
}

# Boolean attributes are smart
input(type: "checkbox", checked: user.subscribed?)
# => <input type="checkbox" checked> (if subscribed)
# => <input type="checkbox"> (if not)

# Void tags handled correctly
img(src: "/logo.png", alt: "Logo")
input(type: "text", name: "email", required: true)
```

---

## Building Components

Components are reusable pieces of UI. Define once, use everywhere:

```ruby
Joys.define(:comp, :user_card) do |user|
  div(cs: "card") {
    img(src: user[:avatar], alt: user[:name])
    h3(user[:name])
    p { txt user[:bio] }  # txt escapes HTML
  }
end

# Render standalone
html = Joys.comp(:user_card, {name: "Alice", bio: "Developer"})

# Or use inside other components
Joys.define(:comp, :user_list) do |users|
  div(cs: "grid") {
    users.each { |user| comp(:user_card, user) }
  }
end
```

#### A Note on Naming Conventions

**Joys** uses a simple global registry for components, pages, and layouts.

For larger applications, we recommend namespacing your definitions to avoid collisions.

Symbols and strings both work, so you can adopt a convention that fits your project.

```ruby
# Define with a path-like string
Joys.define(:comp, 'forms/button') do |text|
  # ...
end
Joys.define(:comp, 'cards/user_profile') do |user|
  # ...
end

# Use them elsewhere

Joys.html do
  div {
    comp 'cards/user_profile', @user
    comp 'forms/button', "Submit"
  }
end
```

This approach keeps your component library organized as it grows.

### Pages

Pages are top-level templates, typically rendered by controllers. Unlike other template solutions, Joys expects each page to explicitly define its layout.

```ruby
Joys.define(:page, :dashboard) do
  layout(:main) {
    push(:title) { txt "Dashboard" }
    
    push(:main) {
      h1("Welcome back!")
      comp(:stats_panel, @stats)
      
      div(cs: "users-grid") {
        @users.each { |u| comp(:user_card, u) }
      }
    }
  }
end

# Render with locals
html = Joys.page(:dashboard, users: User.all, stats: calc_stats)
```

Similar to `content_for` in Rails, HTML may be sent to the layout via the `push(:content_name) {...}` method. The layout establishes placement of this content using `pull(:content_name)`

Note: There is no default `yield`. The `pull` method always requires a symbol. It's up to the user to be explicit in defining where to push content. `push(:main)` or `push(:body)` are sensible defualts, but feel free to use whatever you want.

### Layouts

Layouts provide consistent structure with content slots via the `pull()` method:

```ruby
Joys.define(:layout, :main) do
  html(lang: "en") {
    head {
      title { pull(:title) }
      link(href: "/app.css", rel: "stylesheet")
    }
    body {
      nav { comp(:navbar) }
      main(cs: "container") {
        pull(:main)
      }
    }
  }
end
```
---

## Real-World Example

Here's a more complex nested component with conditions, iterations and all the usual good stuff we expect from templates.

Since Joys is just ruby you have unlimited power to present the content as you wish

```ruby
Joys.define(:comp, :pricing_card) do |plan|
  div(cs: ["card", plan[:featured] && "featured"]) {
    if plan[:featured]
      div("Most Popular", cs: "badge")
    end
    
    h3(plan[:name])
    
    div(cs: "price") {
      span("$", cs: "currency")
      span(plan[:price].to_s, cs: "amount")
      span("/mo", cs: "period")
    }
    
    ul(cs: "features") {
      plan[:features].each do |feature|
        li { raw "&check; #{feature}"}
      end
    }
    
    button(
      plan[:featured] ? "Start Free Trial" : "Choose Plan",
      cs: ["btn", "w-full", (plan[:featured] ? "btn-primary" : "btn-secondary")],
      data: {
        plan: plan[:id],
        price: plan[:price]
      }
    )
  }
end
```

---


## Joy Styling – Scoped, Deduped, Responsive CSS Without the Hassle

Joys doesn’t just generate HTML—it handles CSS like a **pure Ruby, React-level, zero-Node, blazing-fast styling engine**.

With **`styles`**, you can write component CSS **inline**, **scoped**, **deduped**, and **responsive**—all automatically, without ever touching a separate asset pipeline.

---

### Basic Usage

```ruby

# Make sure your layout has a style tag with pull_styles

Joys.define(:layout, :main) do
  doctype
  html {
    head {
      style { pull_styles } # all css will be rendered here
    }
  }
end

# Works when registering coomponents and pages

Joys.define(:comp, :card) do
  div(cs: "card") do
    h1("Hello", cs: "head")
    p("Welcome to Joys!")
  end

  styles do
    css ".card p { color:#333; font-size:0.875rem }"
  end
end

html = Joys.comp(:card)
puts html
```

Note: For multiline css statements you may use Ruby's `%()` method as follows

```ruby
styles do
  css %w(
    .card p { color:#333; font-size:0.875rem }
    .card { background:#fff; border-radius:6px; padding:1rem }
  )
end
```

**Output HTML:**

```html
<div class="card">
  <h1 class="head">Hello</h1>
  <p>Welcome to Joys!</p>
</div>
```

**Generated CSS (automatically appended):**

```css
.card { background:#fff; border-radius:6px; padding:1rem }
.card p { color:#333; font-size:0.875rem }
```

---

### Automatic CSS Scoping

Want your component styles **prefixed automatically** to avoid collisions? Just opt in with `scoped: true`:

```ruby
Joys.define(:comp, :user) do
  styles(scoped: true) do
    css %w(
      .card { background:#fff }
      .head { font-weight:bold }
    )
  end
end
```

**Generated CSS (prefixed with component name):**

```css
.user .card { background:#fff }
.user .head { font-weight:bold }
```

> No more worrying about collisions with other components, layouts, or third-party CSS.

---

### Responsive Media Queries

Joys supports **`min_media`**, **`max_media`**, and **`minmax_media`** right inside your styles. Just pass the width and CSS string.

```ruby
styles do
  css %w(
    .card { padding:1rem }
  )

  media_min "768px", %(
    .card { padding:2rem }
    .head { padding:3rem }
  )

  media_max "480px", ".card { padding:0.5rem }"
  media_minmax "481px", "767px", ".card { padding:1rem }"
end
```

**Generated CSS:**

```css
.card { padding:1rem }

@media (min-width: 768px) {
  .card { padding:2rem }
  .head { padding:3rem }
}

@media (max-width: 480px) {
  .card { padding:0.5rem }
}

@media (min-width: 481px) and (max-width: 767px) {
  .card { padding:1rem }
}
```

* ✅ **Merged automatically**
* ✅ **Deduped**
* ✅ **Sorted by breakpoint**
* ✅ **Scoped if opted-in**

And yes, we also have container queries!

```ruby
styles do
  container_min "768px", ".card {font-size:1.2em}"
  named_container_min "sidebar", "768px", ".card {font-size:2em}"
end
```

**Generated CSS:**

```css
@container (min-width:768px) {
  .card {font-size:1.2em}
}
@container sidebar (min-width:768px) {
  .card {font-size:1.2em}
}
```

---

### Deduplication & Ordering – Built In

Write your component styles wherever you like. Joys will:

* Remove **duplicate selectors** automatically
* Preserve **correct CSS order across nested components**
* Merge **global, page-level, and component-level styles** seamlessly

```ruby
# Even if .card appears in multiple components:
styles do
  css ".card { margin:0 }"
end

# Another component:
styles do
  css ".card { margin:0 }"  # Joys dedupes automatically
end
```

---

### Rendering External CSS

For teams that prefer external CSS files over inline styling, Joys can automatically generate and serve CSS files while maintaining all the performance benefits of consolidated, deduped styles.

#### Basic Usage

Replace `pull_styles` with `pull_external_styles` in your layout:

```ruby
Joys.define(:layout, :main) do
  html(lang: "en") {
    head {
      title { pull(:title) }
      pull_external_styles  # Generates <link> tags instead of inline styles
    }
    body {
      pull(:main)
    }
  }
end
```

#### How It Works

When you render a page, Joys:

1. **Analyzes** which components are actually used
2. **Consolidates** all their styles (base CSS + media queries + container queries)  
3. **Generates** a CSS file named after the component combination
4. **Caches** the file to disk (only creates once per unique component set)
5. **Returns** the appropriate `<link>` tag

```ruby
# Page uses: navbar, user_card, button components
# Generates: /css/comp_navbar,comp_user_card,comp_button.css
# Returns: <link rel="stylesheet" href="/css/comp_navbar,comp_user_card,comp_button.css">
```

#### Configuration

Set your CSS output directory (defaults to `"public/css"`):

```ruby
# config/initializers/joys.rb (Rails)
Joys.css_path = Rails.root.join("public", "assets", "css")

# Or for other frameworks
Joys.css_path = "public/stylesheets"
```

#### Automatic File Management

Joys handles the file lifecycle automatically:

- **Smart naming** - Files named by component combination ensure perfect caching
- **No duplication** - Same component set = same file, served from cache
- **Directory creation** - Creates nested directories as needed
- **Production ready** - Files persist across deployments

#### Example Generated CSS

```ruby
Joys.define(:comp, :card) do
  div(cs: "card") { yield }
  
  styles do
    css ".card { padding: 1rem; background: white; }"
    media_min(768, ".card { padding: 2rem; }")
  end
end

Joys.define(:comp, :button) do
  button(cs: "btn") { yield }
  
  styles(scoped: true) do
    css ".btn { padding: 0.5rem 1rem; }"
    container_min(300, ".btn { width: 100%; }")
  end
end
```

**Generated CSS file:**
```css
.card { padding: 1rem; background: white; }
.button .btn { padding: 0.5rem 1rem; }
@media (min-width: 768px){
  .card { padding: 2rem; }
}
@container (min-width: 300px){
  .button .btn { width: 100%; }
}
```

#### Performance Characteristics

External CSS provides:

- **Browser caching** - CSS files cached separately from HTML
- **Parallel loading** - CSS downloads while HTML processes
- **CDN friendly** - Static files easily cached at edge locations
- **Same deduplication** - All Joys optimizations still apply

Trade-offs vs inline:

- **Extra HTTP request** - One additional round trip
- **Render blocking** - CSS must load before styled rendering
- **Cache complexity** - More moving parts in deployment

#### When to Use External CSS

Choose external CSS when you have:

- **Large stylesheets** (>20KB) where caching outweighs request overhead
- **Strict CSP policies** that prohibit inline styles
- **Team preferences** for traditional CSS file organization
- **CDN optimization** requirements

For most applications under 30-40KB of CSS, inline styles offer better performance and simpler deployment.

#### Rails Integration

External CSS works seamlessly with Rails asset pipeline:

```ruby
# config/initializers/joys.rb
Joys.css_path = Rails.root.join("public", "assets", "joys")

# Your layout
Joys.define(:layout, :application) do
  html {
    head {
      stylesheet_link_tag "application", "data-turbo-track": "reload"
      pull_external_styles  # Joys-generated styles
    }
  }
end
```

#### Deployment Considerations

Since CSS files are generated at runtime:

- Ensure write permissions on your CSS directory
- Consider warming the cache on deployment
- Add `*.css` to your `.gitignore` if files are in your repo path
- For containerized deployments, mount a persistent volume for the CSS directory

#### Mixing with Traditional Assets

External Joys CSS plays nicely with existing stylesheets:

```ruby
head {
  # Your existing global styles
  stylesheet_link_tag "application"
  
  # Component-specific Joys styles  
  pull_external_styles
  
  # Page-specific overrides
  stylesheet_link_tag "admin" if admin_page?
}
```

---

### TL;DR – Why You’ll Never Write CSS the Old Way Again

* **Scoped**: Optional prefixing prevents collisions
* **Deduped**: Automatic removal of duplicate rules
* **Ordered**: Nested components and responsive queries just work
* **Responsive**: min/max/minmax media queries built-in
* **Inline or exportable**: Works in rendering or as a static CSS file

> Write CSS where it belongs: next to your component, in pure Ruby, with **React-level convenience and performance**—all without leaving Ruby.

NOTE: This feature is completely optional. If you are using Tailwind or similar asset compiler, Joys will work just fine with that. However, the integrated css handling greatly simplifies the generation and compilation of styles, using a pure, Node-free process which has zero impact on rendering speed.

## Functional at Heart, But Ready for OOP

Joys is designed to stay out of your way. At its core, it leans functional — you define small, composable render functions instead of verbose boilerplate. But if your project already leans heavily on OOP, Joys can fold right in, allowing you to organize views as classes with inheritance and overrides.

The DSL is the same either way — Joys just adapts.


---

# Joys Rails Integration

## Installation

Add to your Rails app's initializer:

```ruby
require 'joys'
```

Auto-detects Rails and configures integration automatically.

## How It Works

- **Framework Detection**: Checks for `ActionController::Base` and `Rails` 
- **Helper Injection**: Adds all `ActionView::Helpers` to `Joys::Render::Helpers`
- **Context Injection**: Provides `request`, `params`, `current_user`, `session` in templates
- **Controller Integration**: Adds `render_joy` method to all controllers

## Directory Structure

```
app/views/joys/
├── layouts/          # Auto-loaded at boot (production)
├── components/       # Auto-loaded at boot (production) 
└── pages/           # Loaded on-demand
```

## Configuration

```ruby
# Optional - defaults shown
Joys::Config.env = "development"  # or Rails.env
Joys::Config.pages = "app/views/joys/pages"
Joys::Config.layouts = "app/views/joys/layouts"  
Joys::Config.components = "app/views/joys/components"
```

## Controller Usage

```ruby
class HomeController < ApplicationController
  def index
    render_joy :index  # loads app/views/joys/pages/index.rb
  end
  
  def show
    render_joy "users/show", user: User.find(params[:id])
  end
end
```

## Page Templates

### Functional Pattern

```ruby
# app/views/joys/pages/index.rb
data = {title: "Home", nav: link_to("About", "/about")}.freeze

Joys.html {
  layout(:main) {
    push(:title) { txt data[:title] }
    push(:body) { _ data[:nav] }
  }
}
```

### Class Pattern

```ruby
# app/views/joys/pages/index.rb
class IndexPage
  def initialize
    @data = {title: "Home"}.freeze
  end
  
  def render
    data = @data
    Joys.html {
      layout(:main) {
        push(:title) { txt data[:title] }
        push(:body) { _ link_to("About", "/about") }
      }
    }
  end
end

IndexPage.new.render
```

## Rails Helpers

All Rails helpers available directly:

```ruby
Joys.html {
  layout(:main) {
    push(:body) {
      _ link_to("Home", root_path)
      _ image_tag("logo.png", class: "w-8")
      _ form_with model: Post.new do |f|
        f.text_field :title
      end
    }
  }
}
```

## Context Access

```ruby
# Available in all templates
request.referer
params[:id] 
current_user.name
session[:user_id]
```

## Components

```ruby
# app/views/joys/components/card.rb
Joys.define :comp, :card do |title|
  styles { css ".card {padding:1rem;border:1px solid #ddd}" }
  div(cs: "card") { h3 title }
end

# Usage in templates
comp :card, "Hello World"
```

## Page Components

For page-specific components:

```ruby
page_comp(:hero) {
  styles { css ".hero {text-align:center}" }
  section(cs: "hero") { h1 "Welcome" }
}
```

## Layouts

```ruby
# app/views/joys/layouts/main.rb
Joys.define :layout, :main do
  html {
    head { 
      title { pull(:title) }
      pull_styles  # Auto-compiled CSS
    }
    body { pull(:body) }
  }
end
```

## Raw HTML

Use `_` for unescaped HTML:

```ruby
div {
  _ "<strong>Bold</strong>"
  _ link_to("Link", "/")
  txt "Escaped text"  # Auto-escaped
}
```

## Data Passing

```ruby
# Controller
render_joy :show, user: current_user, posts: @posts

# Template  
user_name = @user.name
post_count = @posts.count

Joys.html {
  layout(:main) {
    push(:body) { h1 "Hello #{user_name}" }
  }
}
```

## Environment Behavior

- **Development**: Templates reload on every request
- **Production**: Layouts/components preloaded at boot, pages cached after first render

---

## Markup Processing in Joys

Joys includes a powerful shorthand for processing markup content directly within your templates using the `?` suffix on any tag method.

### Basic Usage

Any tag method can be followed by `?` to process its content through a markup parser:

```ruby
# Process content with your configured markup parser
div?("# Welcome to Joys") 
# => <div><h1>Welcome to Joys</h1></div>

p?("This is **bold** and *italic* text")
# => <p>This is <strong>bold</strong> and <em>italic</em> text</p>

article do
  h2?("## Getting Started")
  p?("Learn how to use the `tag?` methods")
end
```

### Configuration

Configure your preferred markup parser globally:

```ruby
# Using Kramdown
Joys::Config.markup_parser = ->(content) { 
  Kramdown::Document.new(content).to_html 
}

# Using CommonMarker
Joys::Config.markup_parser = ->(content) {
  CommonMarker.render_html(content)
}

# Using any custom parser
Joys::Config.markup_parser = ->(content) {
  MyCustomParser.process(content)
}
```

### 🎯 Recommended: Sparx Parser

For the best developer experience, we recommend **[Sparx](https://github.com/activestylus/sparx)** - a modern markup language designed specifically for the Joys ecosystem:

```ruby
# Install: gem install sparx
Joys::Config.markup_parser = ->(content) { 
  Sparx.parse(content) 
}
```

#### Why Sparx?

Sparx eliminates the frustrations of traditional Markdown with:

- **Consistent syntax** - No more `**bold**` vs `__bold__` confusion
- **Perfect nesting** - Formatting works reliably in complex content
- **Semantic HTML** - Clean, accessible output throughout
- **URL references** - Define URLs once, use them everywhere
- **Responsive images** - Built-in support for modern image requirements
- **Academic citations** - Proper citation handling out of the box

#### Sparx Examples

```ruby
# Clean, consistent formatting
div? do
  p?("*[Bold] and /[italic] with perfect */[nesting]https://example.com")
  # => <p><strong>Bold</strong> and <em>italic</em> with perfect <strong><em><a href="https://example.com">nesting</a></em></strong></p>
end

# Responsive images with art direction
div? do
  p?("i[Hero]@cdn/hero.jpg 400w|hero@2x.jpg 800w")
  # => Generates full <picture> element with responsive sources
end

# Complex content with semantic structure
article? do
  p?("+[Technical Details]{:Performance:100x faster parsing:Output:Semantic HTML5}")
  # => Creates <details> with definition list inside
end
```

### Comparison with Other Methods

```ruby
# Raw text (no processing)
div("## This won't parse")
# => <div>## This won't parse</div>

# Raw HTML (dangerous with user content)
div!("<h1>Raw HTML</h1>") 
# => <div><h1>Raw HTML</h1></div>

# Markup processing (recommended)
div?("# This becomes H1")
# => <div><h1>This becomes H1</h1></div>
```

### Advanced Usage

#### Inline with Other Tags

```ruby
div(cs: "content") do
  h1?("# Article Title")
  div?(css: "prose") do
    p?("First paragraph with *[bold] text")
    blockquote?("> Important quote here")
    ul?("- Item one\n- Item two\n- Item three")
  end
end
```

#### With Component Composition

```ruby
Joys.register(:comp, :blog_post) do |title:, content:|
  article do
    header do
      h1(title)
      time(Time.now.iso8601)
    end
    div?(cs: "content") { raw content }
  end
end

# Usage with Sparx content
Joys.comp(:blog_post, 
  title: "My Article",
  content: Sparx.parse("## Introduction\n\nThis is the *[content]")
)
```

### Performance Notes

- Markup parsing happens at **render time**, not registration time
- Processing is **cached** along with the rest of your template
- For maximum performance with user-generated content, consider pre-processing markup outside the template

### Security

When processing user-generated content, ensure your markup parser is configured for safe mode:

```ruby
# With Sparx safe mode
Joys::Config.markup_parser = ->(content) { 
  Sparx.parse(content, safe: true) 
}
```

The `?` suffix provides a clean, consistent way to integrate markup processing into your Joys templates while maintaining the framework's exceptional performance characteristics.

---

---
## A Word on Performance

Using simple components and views (only 3 layers of nesting) we can see how Joy stacks up:

### Simple Templates (385 chars)

#### ❄️ COLD RENDER (new object per call)
|      | user   | system  | total | real.  |
|------|--------|--------|--------|--------|
|Joys: |0.060535|0.000200|0.060735|0.060736|
|Slim: |0.048344|0.000183|0.048527|0.048530|
|ERB:  |0.301811|0.000808|0.302619|0.302625|
|Phlex:|0.069636|0.000470|0.070106|0.071157|

#### 🔥 HOT RENDER (cached objects)
|      | user   | system  | total  | real   |
|------|--------|---------|--------|--------|
|Joys: |0.065255| 0.000257|0.065512|0.065512|
|Slim: |0.049323| 0.000295|0.049618|0.049695|
|ERB:  |0.309757| 0.001167|0.310924|0.310929|
|Phlex:|0.069663| 0.000141|0.069804|0.069805|

#### 💾 MEMORY USAGE
Joys memory: 532356 bytes
Slim memory: 40503436 bytes
Phlex memory: 8000 bytes
ERB memory: 1669256 bytes

At smaller scales performance is on par with Phlex, which has excellent speed and superior

### Complex Templates (8,000+ chars)

As template complexity grows, Joys starts to really show off its optimizations. This benchmark tests a full dashboard page with 5 components and 2 loops yields:

* Data parsing
* Layouts
* Multiple Content Slots
* Multiple Components
* Several Iterations
* Conditions

### ❄️ COLD RENDER (new object per call)

This is the bare bones benchmark, no "cheating" allowed.

|      | user   | system | total  | real   |
|------|--------|--------|--------|--------|
| Joys |0.051715|0.000364|0.052079|0.052080|
| ERB  |0.520495|0.003696|0.524191|0.524187|
| Slim |6.001650|0.019418|6.021068|6.021013|
| Phlex|0.169567|0.000373|0.169940|0.169938|

Note: Joys achieves its 'cold render' speed by eliminating object overhead and using simple string operations with smart memory management.

### 🔥 HOT RENDER (cached objects)

|      | user    | system | total   | real   |
|------|---------|--------|---------|--------|
|JOYS: | 0.000463|0.000010| 0.000473|0.000473|
|SLIM: | 0.045881|0.000358| 0.046239|0.046243|
|PHLEX:| 0.167631|0.000760| 0.168391|0.168661|
|ERB:  | 0.394509|0.004084| 0.398593|0.398614|

Note: Joys achieves its 'hot render' speed by compiling a template's structure into a highly optimized render function the first time it's called. Subsequent calls with the same component structure reuse this function, bypassing compilation and object allocation, and only interpolating the dynamic data.


### 💾 MEMORY USAGE

Joys memory: 7587400 bytes
Slim memory: 217778600 bytes
Phlex memory: 9956000 bytes
ERB memory: 7264240 bytes

Even without caching, Joys is rendering at around 50 milliseconds.

The real performance comes after caching at half a millisecond.

That's not just fast, its _ludicrous speed_ 🚀 All thanks to Joys's one-time compilation and caching of the template structure.

But don't take our word for it:

```
gem install erb slim phlex joys

# Simple benchmark
ruby text/bench/simple.rb

# Complex benchmark
ruby text/bench/deep.rb
```

Note: If you have any additions, critiques or input on these benchmarks please submit a pull request.

### Performance Philosophy

Joys attains its incredible speed through:

1. **Precompiled layouts** - Templates compile once, render many
2. **Direct string building** - No intermediate AST or object allocation
3. **Smart caching** - Components cache by arguments automatically
4. **Zero abstraction penalty** - It's just method calls and string concatenation

All achieved without C or Rust. Just plain old Ruby, with a core of under 500 lines of code. 

---

## The Final Assessment: When to Use Joys

- You want **high-throughput** Ruby APIs serving HTML.
- You want **memory-tight rendering** in constrained environments.
- You want to **replace ERB** without giving up **developer happiness**.
- You want to build functional, composable user interfaces

## When Not to Use Joys

- You need **streaming HTML** (use ERB, Slim & Phlex instead)
- You want maturity and community. This library is quite new!
- You prefer HTML markup over a Ruby DSL 

Read on for the full scope of features and then decide if it's worth giving Joys a try!

## Frequently Asked Questions

### What versions of Ruby are supported?

Joys is compatible with modern Ruby versions (≥2.6) and tested on recent releases for performance and feature stability.

### How does Joys handle escaping and injection attacks?

Joys defaults to HTML-escaping text, making output safe unless explicitly marked as raw. Use txt for safe user content, and raw only for trusted HTML fragments.

### Can Joys be used outside Rails?

Yes, Joys is a pure Ruby templating engine and works in any Ruby project, not just Rails. Rails integration is completely optional.

### Do Rails helpers and SafeBuffer work with Joys?

All Rails helpers, SafeBuffer, and routing helpers work natively within Joys components and pages, so migration is straightforward and full-featured.

### How are components and layouts organized?

Joys uses a global registry for components, pages, and layouts. Namespacing and convention (symbols or strings) are supported for large codebases to avoid naming collisions.

### What should I do if I see an error?

Any runtime errors or misuse are clearly displayed in the stack trace, making debugging direct and transparent. There are very few edge case errors, and all are intentionally explicit to ease troubleshooting.

### Is it really that fast, or is this just hype?

Joys is exactly as fast as advertised after much battle testing, benching and profiling it to oblivion. If you find any flaw in our testing methodology please let us know how we can improve or level the playing field.

### Why Not Just Use Phlex instead?

Truthfully, there is no compelling reason not to use Phlex. It's mature, blazing fast and smart on memory consumption. Joys is very much inspired by this framework. The APIs are strikingly similar, however Joys adopts a more functional/minimal paradigm for composition. It also comes with UI styling baked in (something not seen in any other ruby templating library).

---

## License

MIT

---

Joys isn’t just a templating engine. It’s a new definition of what rendering in Ruby should feel like: fast, safe, and joyful.

*Built with ❤️ and a relentless focus on performance.*

---

## Thanks and Gratitude

Massive shout-out to the Masatoshi Seki (ERB), Daniel Mendler (Slim), Daniel Mendler (Phlex/P2), and Jonathan Gillette (Markaby). All of you have made countless lives so much easier. The ruby community thanks you for your service!

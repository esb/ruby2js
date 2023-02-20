---
order: 2
title: Options
top_section: Introduction
category: options
---

Ruby2JS provides quite a few options to help you configure your transpilation process.

{% toc %}

## Preset Configuration

Starting with Ruby2JS 5.1, we've created a single "preset" configuration option which provides you with a sane set of modern conversion defaults. This includes:

* The [Functions](/docs/filters/functions), [ESM](/docs/filters/esm), and [Return](/docs/filters/return) filters
* ES2021 support
* Underscored fields for ivars (`@ivar` becomes `this._ivar`)
* Identity comparison (`==` becomes `===`)

You can pass `preset: true` as an option to the Ruby2JS API or `--preset` via the CLI. In addition, you can set it in your configuration file should you choose to have one.

Finally, for maximum portability (great for code sharing!) you can use a **magic comment** at the top of a file to set the preset mode:

```
# ruby2js: preset
```

You can also configure additional filters plus eslevel, and disable preset filters individually too:

```
# ruby2js: preset, filters: camelCase

# ruby2js: preset, eslevel: 2022

# ruby2js: preset, disable_filters: return
```

## Create Your Own Configuration

There are a number of configuration options available for both the converter itself as well as any filters you choose to add.

If you find yourself needing a centralized location to specify these options for your project, create an `config/ruby2js.rb` file in your project root. Example:

```ruby
preset

filter :camelCase

eslevel 2022

include_method :class
```

If you need to specify a custom location for your config file, you can use the `config_file` argument in the Ruby DSL, or the `-C` or `--config` options in the CLI.

Otherwise, Ruby2JS will automatically file the `config/ruby2js.rb` file in the current working directory.

```ruby
# some_other_script.rb

ruby_code = <<~RUBY
  export toggle_menu_icon = ->(button) do
    button.query_selector_all(".icon").each do |item|
      item.class_list.toggle "not-shown"
    end
    button.query_selector(".icon:not(.not-shown)").class_list.add("shown")
  end
RUBY

js_code = Ruby2JS.convert(ruby_code) # picks up config automatically
```

Keep reading for all the options you can add to the configuration file.

## Auto Exports

The ESM filter has an option to automatically export all top
level constants, methods, classes, and modules.

```ruby
# Configuration

autoexports true # or :default
```

```ruby
puts Ruby2JS.convert("X = 1", filters: [:esm], autoexports: true)
```

If the `autoexports` option is `:default`, and there is only one top level
module, class, method or constant it will automatically be exported as
`default`.  If there are multiple, each will be exported with none of them as
default.

## Auto Imports

The ESM filter has an option to automatically import selected
modules if a given constant is encountered in the parsing of the source.
See [the ESM filter](filters/esm#autoimports) for details.

```ruby
# Configuration

autoimport [:LitElement], 'lit'
```

```ruby
puts Ruby2JS.convert('class MyElement < LitElement; end',
  preset: true, autoimports: {[:LitElement] => 'lit'})
```

## Binding

If the [binding](https://ruby-doc.org/core-3.0.0/Binding.html) option is
provided, expressions passed in back-tic <code>``</code> or `%x()` expressions
will be evaluated in the host context.  This is very unsafe if there is any
possibility of the script being provided by external sources; in such cases
[ivars](#ivars) are a much better alternative.

```ruby
puts Ruby2JS.convert('x = `Dir["*"]`', binding: binding)
```

## Comparison

While both Ruby and JavaScript provide double equal and triple equal
operators, they do different things.  By default (or by selecting
`:equality`), Ruby double equals is mapped to JavaScript double equals and
Ruby triple equals is mapped to JavaScript triple equals.  By selecting
`:identity`), both Ruby double equals and Ruby triple equals are mapped to
JavaScript triple equals.

```ruby
# Configuration

identity_comparison
```

```ruby
puts Ruby2JS.convert('a == b', comparison: :identity)
```

## Defs

List of methods and properties for classes and modules imported via
[autoimports](#auto-imports).  Prepend an `@` for properties.

```ruby
# Configuration

defs({A: [:x,:@y]})
```

```ruby
puts Ruby2JS.convert('class C < A; def f; x; end; end',
  defs: {A: [:x,:@y]}, filters: [:esm], eslevel: 2020, autoimports: {A: 'a.js'})
```

## ESLevel

Determine which ECMAScript level the resulting script will target.  See
[eslevels](eslevels) for details.

```ruby
# Configuration

eslevel 2021
```

```ruby
puts Ruby2JS.convert("x ||= 1", eslevel: 2021)
```

## Exclude

Many filters include multiple conversions; and there may be cases where
a some of these conversions interfere with the intent of the code in
question.  The `exclude` option allows you to eliminate selected methods
from being eligible for conversion.
See also [Include](#include), [Include All](#include-all), and
[Include Only](#include-only).

```ruby
puts Ruby2JS.convert(
  "jQuery.each(x) do |i,v| text += v.textContent; end",
  preset: true, exclude: [:each]
)
```

## Filters

The `filters` option (`filter` in the configuration file) allows you to control which available filters are applied to a specific conversion.  

```ruby
# Configuration

filter :functions
filter :camelCase
```

```ruby
puts Ruby2JS.convert("my_list.empty?", filters: [:functions, :camelCase])
```

You can also remove filters if you're using the preset configuration and you want to take one out:

```ruby
# Configuration

preset

remove_filter :esm
```

See our documentation for various filters over on the sidebar.

## Include

Some filters include conversions that may interfere with common usage and therefore are only available via opt-in.  The `include` option (`include_method` in the configuration file) allows you to select additional methods to be eligible for conversion.

```ruby
# Configuration

include_method :class
```

```ruby
puts Ruby2JS.convert("object.class", preset: true, include: [:class])
```

See also
[Exclude](#exclude), [Include All](#include-all), and 
[Include Only](#include-only).

## Include All

Some filters include conversions that may interfere with common usage and
therefore are only available via opt-in.  The `include_all` option allows you to
opt into all available conversions.  See also [Exclude](#exclude),
[Include](include), and [Include Only](#include-only).

```ruby
puts Ruby2JS.convert("object.class", preset: true, include_all: true)
```

## Include Only

Many filters include multiple conversions; and there may be cases where
a some of these conversions interfere with the intent of the code in
question.  The `include-only` option allows you to selected which methods
are eligible for conversion.
See also [Exclude](#exclude), [Include](#include), and 
[Include All](#include-all).

```ruby
puts Ruby2JS.convert("list.max()", preset: true, include_only: [:max])
```

## Import From Skypack

Some filters like [ActiveFunctions](filters/active_functions) will generate
import statements.  If the `import_from_skypack` option is set, these import
statements will make use of the [skypack](https://www.skypack.dev/) CDN.

```ruby
puts Ruby2JS.convert("x.present?",
  preset: true, filters: [:active_functions], import_from_skypack: true)
```

## IVars

Instance Variables (ivars) allow you to supply data to the script.  A common
use case is when the script is a view template.  See also [scope](#scope).


```ruby
puts Ruby2JS.convert("X = @x", ivars: {:@x => 1})
```

## Or

Introduced in ES2020, the 
[Nullish Coalescing](https://github.com/tc39/proposal-nullish-coalescing#nullish-coalescing-for-javascript)
operator provides an alternative implementation of the *or* operator.  Select
which version of the operator you want using the `or` option.  Permissible
values are `:logical` and `:nullish` with the default being logical.

```ruby
# Configuration

nullish_or
```

```ruby
puts Ruby2JS.convert("a || b", or: :nullish, eslevel: 2020)
```

## Scope

Make all Instance Variables (ivars) in a given scope available to the
script.  See also [ivars](#ivars).

```ruby
require "ruby2js"
@x = 5
puts Ruby2JS.convert("X = @x", scope: self)
```

## Template Literal Tags

The [Tagged Templates](filters/tagged-templates) filter will convert method
calls to a set of methods you provide to tagged template literal syntax.

```ruby
# Configuration

template_literal_tags [:color]
```

```ruby
Ruby2JS.convert("color 'red'",
  preset: true, filters: [:tagged_templates], template_literal_tags: [:color])
```

## Underscored private

Private fields in JavaScript classes differ from instance variables in Ruby classes in that subclasses can't access private fields in parent classes.  The `underscored_private` (`underscored_ivars` in the configuration file) option makes such variables public but prefixed with an underscore instead.

```ruby
# Configuration

underscored_ivars
```

```ruby
puts Ruby2JS.convert('class C; def initialize; @a=1; end; end', eslevel: 2020,
  underscored_private: true)
```

## Width

Ruby2JS tries, but does not guarantee, to produce output limited to 80 columns
in width.  You can change this value with the `width` option.

```ruby
puts Ruby2JS.convert("puts list.last unless list.empty?\n", preset: true, width: 50)
```

## Configuring JavaScript Packages

When configuring the Node version of Ruby2JS, note that the options are expressed in JSON format instead of
as a Ruby Hash.  The following rules will help explain the conversions
necessary:

  * use strings for symbols
  * for `functions`, specify string names not module names
  * for `autoimports`, specify keys as strings, even if key is an array
  * not supported: `binding`, `ivars`, `scope`

Currently the new configuration file format (`config/ruby2js.rb`) isn't supported by the Node version of Ruby2JS either.

An example of all of the supported options:

```json
{
  "autoexports": true,
  "autoimports": {"[:LitElement]": "lit"},
  "comparison": "identity",
  "defs": {"A": ["x", "@y"]},
  "eslevel": 2021,
  "exclude": ["each"],
  "filters": ["functions"],
  "include": ["class"],
  "include_all": true,
  "include_only": ["max"],
  "import_from_skypack": true,
  "or": "nullish",
  "require_recurse": true,
  "preset": true,
  "template_literal_tags": ["color"],
  "underscored_private": true,
  "width": 40
}
```

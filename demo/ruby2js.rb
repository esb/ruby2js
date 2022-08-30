#!/usr/bin/env ruby
#
# Interactive demo of conversions from Ruby to JS.

# --port and --install options require wunderbar.
#
# Installation
# ----
#
#   Web server set up to run CGI programs?
#     $ ruby ruby2js.rb --install=/web/docroot
#
#   Want to run a standalone server?
#     $ ruby ruby2js.rb --port=8080
#
#   Want to run from the command line?
#     $ ruby ruby2js.rb [options] [file]
#
#       try --help for a list of supported options

# support running directly from a git clone
$:.unshift File.absolute_path('../../lib', __FILE__)
require 'ruby2js/demo'
require 'cgi'
require 'pathname'

def parse_request(env=ENV)

  # autoregister filters
  filters = Ruby2JS::Filter.autoregister($:.first)

  # web/CGI query string support
  selected = env['PATH_INFO'].to_s.split('/')
  env['QUERY_STRING'].to_s.split('&').each do |opt|
    key, value = opt.split('=', 2)
    if key == 'ruby'
      @ruby = CGI.unescape(value)
    elsif key == 'filter'
      selected = CGI.unescape(value).split(',')
    elsif value
      ARGV.push("--#{key}=#{CGI.unescape(value)}")
    else
      ARGV.push("--#{key}")
    end
  end

  # extract options from the argument list
  options = {}
  options[:include] = [:class] if ARGV.delete('--include-class')
  @live = ARGV.delete('--live')
  wunderbar_options = []

  require 'optparse'

  opts = OptionParser.new
  opts.banner = "Usage: #$0 [options] [file]"

  opts.on('--preset', "use sane defaults (modern eslevel & common filters)") {options[:preset] = true}

  opts.on('-C', '--config [FILE]', "configuration file to use (default is config/ruby2js.rb)") {|filename|
    options[:config_file] = filename
  }

  opts.on('--autoexports [default]', "add export statements for top level constants") {|option|
    options[:autoexports] = option ? option.to_sym : true
  }

  opts.on('--autoimports=mappings', "automatic import mappings, without quotes") {|mappings|
    options[:autoimports] = Ruby2JS::Demo.parse_autoimports(mappings)
  }

  opts.on('--defs=mappings', "class and module definitions") {|mappings|
    options[:defs] = Ruby2JS::Demo.parse_defs(mappings)
  }

  opts.on('--equality', "double equal comparison operators") {options[:comparison] = :equality}

  # autoregister eslevels
  Dir["#{$:.first}/ruby2js/es20*.rb"].sort.each do |file|
    eslevel = File.basename(file, '.rb')
    filters[eslevel] = file

    opts.on("--#{eslevel}", "ECMAScript level #{eslevel}") do
      @eslevel = eslevel[/\d+/]
      options[:eslevel] = @eslevel.to_i
    end
  end

  opts.on('--exclude METHOD,...', "exclude METHOD(s) from filters", Array) {|methods|
    options[:exclude] ||= []; options[:exclude].push(*methods.map(&:to_sym))
  }

  opts.on('-f', '--filter NAME,...', "process using NAME filter(s)", Array) do |names|
    selected.push(*names)
  end

  opts.on('--filepath [PATH]', "supply a path if stdin is related to a source file") do |filepath|
    options[:file] = filepath
  end

  opts.on('--identity', "triple equal comparison operators") {options[:comparison] = :identity}

  opts.on('--import_from_skypack', "use Skypack for internal functions import statements") do
    options[:import_from_skypack] = true
  end

  opts.on('--include METHOD,...', "have filters process METHOD(s)", Array) {|methods|
    options[:include] ||= []; options[:include].push(*methods.map(&:to_sym))
  }

  opts.on('--include-all', "have filters include all methods") do
    options[:include_all] = true
  end

  opts.on('--include-only METHOD,...', "have filters only process METHOD(s)", Array) {|methods|
    options[:include_only] ||= []; options[:include_only].push(*methods.map(&:to_sym))
  }

  opts.on('--ivars @name:value,...', "set ivars") {|ivars|
    options[:ivars] ||= {}
    options[:ivars].merge! ivars.split(/(?:^|,)\s*(@\w+):/)[1..-1].each_slice(2).
      map {|name, value| [name.to_sym, value]}.to_h
  }

  opts.on('--logical', "use '||' for 'or' operators") {options[:or] = :logical}

  opts.on('--nullish', "use '??' for 'or' operators") {options[:or] = :nullish}

  opts.on('--require_recursive', "import all symbols defined by processing the require recursively") {options[:require_recursive] = true}

  opts.on('--strict', "strict mode") {options[:strict] = true}

  opts.on('--template_literal_tags tag,...', "process TAGS as template literals", Array) {|tags|
    options[:template_literal_tags] ||= []; options[:template_literal_tags].push(*tags.map(&:to_sym))
  }

  opts.on('--underscored_private', "prefix private properties with an underscore") do
    options[:underscored_private] = true
  end

  # shameless hack.  Instead of repeating the available options, extract them
  # from the OptionParser.  Exclude default options and es20xx options.
  options_available = opts.instance_variable_get(:@stack).last.list.
    map {|opt| [opt.long.first[2..-1], opt.arg != nil]}.
    reject {|name, arg| %w{equality logical}.include?(name) || name =~ /es20\d\d/}.to_h

  opts.separator('')

  opts.on('--port n', Integer, 'start a webserver') do |n|
    wunderbar_options.push "--port=#{n}"
  end

  opts.on('--install path', 'install as a CGI program') do |path|
    wunderbar_options.push "--install=#{path}"
  end

  begin
    opts.parse!
  rescue Exception => $load_error
    raise unless defined? env and env['SERVER_PORT']
  end

  ARGV.push(*wunderbar_options)
  ARGV.push @live if @live
  require 'wunderbar' unless wunderbar_options.empty?

  # load selected filters
  options[:filters] = Ruby2JS::Filter.require_filters(selected)

  return options, selected, options_available
end

options = parse_request.first

if (not defined? Wunderbar or not env['SERVER_PORT']) and not @live
  # command line support
  if ARGV.length > 0
    options[:file] = ARGV.first
    puts Ruby2JS.convert(File.read(ARGV.first), options).to_s
  else
    puts Ruby2JS.convert($stdin.read, options).to_s
  end  

else
  require 'wunderbar'

  def walk(ast, indent='', tail='', last=true)
    return unless ast
    _div class: (ast.loc ? 'loc' : 'unloc') do
      _ indent
      _span.hidden 's(:'
      _ ast.type
      _span.hidden ',' unless ast.children.empty?

      if ast.children.any? {|child| Parser::AST::Node === child}
        ast.children.each_with_index do |child, index|
          ctail = index == ast.children.length - 1 ? ')' + tail : ''
          if Parser::AST::Node === child
            walk(child, "  #{indent}", ctail, last && !ctail.empty?)
          else
            _div do
              _ "#{indent}  #{child.inspect}"
              _span.hidden "#{ctail}#{',' unless last && !ctail.empty?}"
              _ ' ' if last && !ctail.empty?
            end
          end
        end
      else
        ast.children.each_with_index do |child, index|
          _ " #{child.inspect}"
          _span.hidden ',' unless index == ast.children.length - 1
        end
        _span.hidden ")#{tail}#{',' unless last}"
        _ ' ' if last
      end
    end
  end

  # web server support
  _html do
    options, selected, options_available = parse_request env
    _title 'Ruby2JS'

    base = env['REQUEST_URI'].split('?').first
    base = base[0..-env['PATH_INFO'].length] if env['PATH_INFO']
    base += '/' unless base.end_with? '/'
    _base href: base

    _style %{
      .js.editor { background-color: #ffffcc }
      .ruby.editor { resize: vertical; overflow: auto; height: 200px; background-color: #ffeeee; margin-bottom: 5px; }
      .ruby .cm-wrap { background-color: #ffeeee; height: 100% }
      .js .cm-wrap { background-color: #ffffdd; height: 100% }
      .ruby .cm-wrap .cm-content .cm-activeLine { background-color: #ffdddd; margin-right: 2px }
      .js .cm-wrap .cm-content .cm-activeLine { background-color: #ffffcc; margin-right: 2px }

      .unloc {background-color: yellow}
      .loc {background-color: white}
      .loc span.hidden, .unloc span.hidden {font-size: 0}
      .container.narrow-container {padding: 0; margin: 0 3%; max-width: 91%}
      .exception {background-color:#ff0; margin: 1em 0; padding: 1em; border: 4px solid red; border-radius: 1em}

      #{(@live ? %q{
      sl-menu { display: none }
      .narrow-container pre {padding: 0 1rem}
      .narrow-container h1.title, .narrow-container h2.title {margin: 0.5rem 0}
      } : %q{
      svg {height: 4em; width: 4em; transition: 0.5s}
      svg:hover {height: 8em; width: 8em}
      textarea.ruby {background-color: #ffeeee; margin-bottom: 0.4em}
      pre.js {background-color: #ffffcc}
      h2 {margin-top: 0.4em}

      .dropdown { position: relative; display: none; }
      .dropdown-content { display: none; position: absolute; background-color: #f9f9f9; min-width: 180px; box-shadow: 0px 8px 16px 0px rgba(0,0,0,0.2); padding: 12px 16px; z-index: 1; }

      /* below is based on bootstrap
      https://cdn.jsdelivr.net/npm/bootstrap@5.0.0-beta1/dist/css/bootstrap.min.css
      */

      :root{--bs-base-font-size: 16px;--bs-font-sans-serif:system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,"Noto Sans","Liberation Sans",sans-serif,"Apple Color Emoji","Segoe UI Emoji","Segoe UI Symbol","Noto Color Emoji";--bs-font-monospace:SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace}
      html{font-size:var(--bs-base-font-size)}
      body{margin:0;font-family:var(--bs-font-sans-serif);font-size:1rem;font-weight:400;line-height:1.5;color:#212529;background-color:#fff;-webkit-text-size-adjust:100%;-webkit-tap-highlight-color:transparent}
      a{color:#0d6efd;text-decoration:underline}
      a:hover{color:#0a58ca}
      svg{vertical-align:middle}
      label{display:inline-block}
      input,select,textarea{margin:0;font-family:inherit;font-size:inherit;line-height:inherit}
      select{text-transform:none}
      select{word-wrap:normal}
      [type=submit]{-webkit-appearance:button}
      .container{width:100%;padding-right:var(--bs-gutter-x,.75rem);padding-left:var(--bs-gutter-x,.75rem);margin-right:auto;margin-left:auto}
      .form-control{display:block;width:100%;padding:.375rem .75rem;font-size:1rem;font-weight:400;line-height:1.5;color:#212529;background-color:#fff;background-clip:padding-box;border:1px solid #ced4da;-webkit-appearance:none;-moz-appearance:none;appearance:none;border-radius:.25rem;transition:border-color .15s ease-in-out,box-shadow .15s ease-in-out}
      .btn:focus{outline:0;box-shadow:0 0 0 .25rem rgba(13,110,253,.25)}

      .btn-primary{color:#fff;background-color:#0d6efd;border-color:#0d6efd}
      .btn-primary:hover{color:#fff;background-color:#0b5ed7;border-color:#0a58ca}
      .btn-primary:focus{color:#fff;background-color:#0b5ed7;border-color:#0a58ca;box-shadow:0 0 0 .25rem rgba(49,132,253,.5)}
      .btn-primary:active{color:#fff;background-color:#0a58ca;border-color:#0a53be}
      .btn-primary:active:focus{box-shadow:0 0 0 .25rem rgba(49,132,253,.5)}
      .btn-primary:disabled{color:#fff;background-color:#0d6efd;border-color:#0d6efd}
      }).strip}
    }

    _div.container.narrow_container do
      if @live
        _h1.title.is_size_4 'Ruby'

        _sl_dialog.option! label: "Option" do
          _sl_input
          _sl_button "Close", slot: "footer", type: "primary"
        end
      else
        _a href: 'https://www.ruby2js.com/docs/' do
          _ruby2js_logo
          _ 'Ruby2JS'
        end

        def _sl_select(&block)
          _select(&block)
        end

        def _sl_dropdown(&block)
          _div.dropdown(&block)
        end

        def _sl_button(text, options, &block)
          _button.btn text, id: options[:id]
        end

        def _sl_menu(&block)
          _div.dropdown_content(&block)
        end

        def _sl_menu_item(name, args)
          if args.include? :checked
            _div do
              _input type: 'checkbox', **args
              _span name
            end
          else
            _option name, args
          end
        end

        def _sl_checkbox(name, args)
          _input type: 'checkbox', **args
          _label name, for: args[:id]
        end
      end

      _form method: 'post' do
        _div data_controller: @live && 'ruby' do
          _textarea.ruby.form_control @ruby, name: 'ruby', rows: 8,
            placeholder: 'Ruby source'
        end

        _div.options data_controller: @live && 'options' do
          _input.btn.btn_primary type: 'submit', value: 'Convert', 
            style: "display: #{@live ? 'none' : 'inline'}"

          _label 'ESLevel:', for: 'eslevel'
          if @live
            _sl_dropdown.eslevel! name: 'eslevel' do
              _sl_button @eslevel || 'default', slot: 'trigger', caret: true
              _sl_menu do
                _sl_menu_item 'default', checked: !@eslevel || @eslevel == 'default'
                Dir["#{$:.first}/ruby2js/es20*.rb"].sort.each do |file|
                  eslevel = File.basename(file, '.rb').sub('es', '')
                  _sl_menu_item eslevel, value: eslevel, checked: @eslevel == eslevel
                end
              end
            end
          else
            _select name: 'eslevel', id: 'eslevel' do
              _option 'default', selected: !@eslevel || @eslevel == 'default'
              Dir["#{$:.first}/ruby2js/es20*.rb"].sort.each do |file|
                eslevel = File.basename(file, '.rb').sub('es', '')
                _option eslevel, value: eslevel, selected: @eslevel == eslevel
              end
            end
          end

          _sl_checkbox 'Show AST', id: 'ast', name: 'ast', checked: !!@ast

          _sl_dropdown.filters! close_on_select: 'false' do
            _sl_button 'Filters', slot: 'trigger', caret: true
            _sl_menu do
              Dir["#{$:.first}/ruby2js/filter/*.rb"].sort.each do |file|
                filter = File.basename(file, '.rb')
                next if filter == 'require'
                _sl_menu_item filter, name: filter,
                  checked: selected.include?(filter)
              end
            end
          end

          _sl_dropdown.options! close_on_select: 'false' do
            _sl_button 'Options', slot: 'trigger', caret: true
            _sl_menu do
              checked = options.dup
              checked[:identity] = options[:comparison] == :identity
              checked[:nullish] = options[:or] == :nullish

              options_available.each do |option, args|
                next if option == 'filter'
                next if option.start_with? 'require_'
                _sl_menu_item option, name: option,
                  checked: checked[option.to_sym],
                  data_args: options_available[option]
              end
            end
          end
        end
      end
      
      _script %{
        // determine base URL and what filters and options are selected
        let base = new URL(document.getElementsByTagName('base')[0].href).pathname;
        let filters = new Set(window.location.pathname.slice(base.length).split('/'));
        filters.delete('');
        let options = {};
        for (let match of window.location.search.matchAll(/(\\w+)(=([^&]*))?/g)) {
          options[match[1]] = match[3] && decodeURIComponent(match[3]);
        };
        if (options.filter) options.filter.split(',').forEach(option => filters.add(option));

        function updateLocation(force = false) {
          let location = new URL(base, window.location);
          location.pathname += Array.from(filters).join('/');

          let search = [];
          for (let [key, value] of Object.entries(options)) {
            search.push(value === undefined ? key : `${key}=${encodeURIComponent(value)}`);
          };

          location.search = search.length === 0 ? "" : `${search.join('&')}`;
          if (!force && window.location.toString() == location.toString()) return;

          history.replaceState({}, null, location.toString());

          if (document.getElementById('js').style.display === 'none') return;

          // fetch updated results
          let ruby = document.querySelector('textarea[name=ruby]').textContent;
          let ast = document.getElementById('ast').checked;
          let headers = {
            'Content-Type': 'application/json',
            'Accept': 'application/json'
          }

          fetch(location,
            {method: 'POST', headers, body: JSON.stringify({ ruby, ast })}
          ).then(response => {
            return response.json();
          }).
          then(json => {
            document.querySelector('#js pre').textContent = json.js || json.exception;

            let parsed = document.querySelector('#parsed');
            if (json.parsed) parsed.querySelector('pre').outerHTML = json.parsed;
            parsed.style.display = json.parsed ? "block" : "none";

            let filtered = document.querySelector('#filtered');
            if (json.filtered) filtered.querySelector('pre').outerHTML = json.filtered;
            filtered.style.display = json.filtered ? "block" : "none";
          }).
          catch(console.error);
        }

        // show dropdowns (they only appear if JS is enabled)
        let dropdowns = document.querySelectorAll('.dropdown');
        for (let dropdown of dropdowns) {
          dropdown.style.display = 'inline-block';
          let content = dropdown.querySelector('.dropdown-content');
          content.style.opacity = 0;
          content.style.display = 'none';

          // toggle dropdown
          dropdown.querySelector('button').addEventListener('click', event => {
            event.preventDefault();
            content.style.transition = '0s';
            content.style.display = 'block';
            content.style.zIndex = 1;
            content.style.opacity = 1 - content.style.opacity;
          });

          // make dropdown disappear when mouse moves away
          let focus = false;
          dropdown.addEventListener('mouseover', () => {focus = true});
          dropdown.addEventListener('mouseout', event => {
            if (content.style.opacity === 0) return;
            focus = false;
            setTimeout( () => {
              if (!focus) {
                content.style.transition = '0.5s';
                content.style.opacity = 0;
                setTimeout( () => { content.style.zIndex = -1; }, 500);
              }
            }, 500)
          })
        };

        // add/remove eslevel options
        document.getElementById('eslevel').addEventListener('change', event => {
          let value = event.target.value;
          if (value !== "default") options['es' + value] = undefined;
          for (let option of event.target.querySelectorAll('option')) {
            if (option.value === 'default' || option.value === value) continue;
            delete options['es' + option.value];
          };
          updateLocation();
        });

        // add/remove filters based on checkbox
        let dropdown = document.getElementById('filters');
        for (let filter of dropdown.querySelectorAll('input[type=checkbox]')) {
          filter.addEventListener('click', event => {
            let name = event.target.name;
            if (!filters.delete(name)) filters.add(name);
            updateLocation();
          });
        }

        // add/remove options based on checkbox
        dropdown = document.getElementById('options');
        for (let option of dropdown.querySelectorAll('input[type=checkbox]')) {
          option.addEventListener('click', event => {
            let name = event.target.name;

            if (name in options) {
              delete options[name];
            } else if (option.dataset.args) {
              options[name] = prompt(name);
            } else {
              options[name] = undefined;
            };

            updateLocation();
          })
        };

        // allow update of option
        for (let span of document.querySelectorAll('input[data-args] + span')) {
          span.addEventListener('click', event => {
            let name = span.previousElementSibling.name;
            options[name] = prompt(name, decodeURIComponent(options[name] || ''));
            span.previousElementSibling.checked = true;
            updateLocation();
          })
        }

        // refesh on "Show AST" change
        document.getElementById('ast').addEventListener('click', updateLocation);
      }

      _div_? do
        raise $load_error if $load_error

        options[:eslevel] = @eslevel.to_i if @eslevel

        parsed = Ruby2JS.parse(@ruby).first if @ast and @ruby

        _div.parsed! style: "display: #{@ast ? 'block' : 'none'}" do
          _h2.title.is_size_6 'AST'
          _pre {_ {walk(parsed)}}
        end

        ruby = Ruby2JS.convert(@ruby, options) if @ruby

        _div.filtered! style: "display: #{@ast && parsed != ruby.ast ? 'block' : 'none'}" do
          _h2.title.is_size_6 'filtered AST'
          _pre {walk(ruby.ast) if ruby}
        end

        _div.js! data_controller: @live && 'js', style: "display: #{@ruby ? 'block' : 'none'}" do
          _h2.title.is_size_4 'JavaScript'
          _pre.js ruby.to_s
        end
      end
    end
  end

  def _ruby2js_logo
    _svg width: '100%', height: '100%', viewBox: '0 0 278 239', version: '1.1', xlink: 'http://www.w3.org/1999/xlink', space: 'preserve', 'xmlns:serif' => 'http://www.serif.com/', style: 'fill-rule:evenodd;clip-rule:evenodd;stroke-linecap:round;stroke-linejoin:round;stroke-miterlimit:10;' do
      _g transform: 'matrix(0.97805,-0.208368,0.208368,0.97805,-63.5964,16.8613)' do
        _path d: 'M43.591,115.341L92.572,45.15L275.649,45.276L322,113.639L183.044,261.9L43.591,115.341Z', style: 'fill:rgb(201,38,19);'
        _g.Layer1! transform: 'matrix(0.762386,0,0,0.762386,-83.8231,-163.857)' do
          _g transform: 'matrix(1,0,0,1,1,0)' do
            _path d: 'M253,412.902L323.007,416.982L335.779,302.024L433.521,467.281L346.795,556.198L253,412.902Z', style: 'fill:url(#_Linear1);'
          end
          _g transform: 'matrix(1,0,0,1,90,0)' do
            _path d: 'M260.802,410.567L312.405,427.307L345.625,407.012L286.376,341.482L301.912,316.368L348.735,322.338L402.088,408.236L360.798,450.037L317.951,497.607L260.802,410.567Z', style: 'fill:url(#_Linear2);'
          end
        end
        _g transform: 'matrix(1,0,0,1,-71.912,-102.1)' do
          _path d: 'M133.132,219.333L241.936,335.629L190.73,219.333L133.132,219.333ZM205.287,219.333L255.212,345.305L306.383,219.333L205.287,219.333ZM374.878,219.333L320.94,219.333L267.853,335.345L374.878,219.333ZM211.57,207.009L302.227,207.009L256.899,159.664L211.57,207.009ZM334.854,155.614L268.834,155.614L314.068,202.862L334.854,155.614ZM176.816,155.614L198.271,204.385L244.966,155.614L176.816,155.614ZM375.017,207.009L345.969,163.438L326.802,207.009L375.017,207.009ZM137.348,207.009L184.868,207.009L166.129,164.411L137.348,207.009ZM163.588,147L348.228,147L393.912,215.526L254.956,364L116,217.43L163.588,147Z', style: 'fill:none;fill-rule:nonzero;stroke:rgb(255,248,195);stroke-width:5px;'
        end
        _g transform: 'matrix(0.76326,0,0,0.76326,-88.595,-169.24)' do
          _g opacity: '0.44' do
            _g.j! transform: 'matrix(0.46717,0,0,0.46717,186.613,178.904)' do
              _path d: 'M165.65,526.474L213.863,497.296C223.164,513.788 231.625,527.74 251.92,527.74C271.374,527.74 283.639,520.13 283.639,490.53L283.639,289.23L342.842,289.23L342.842,491.368C342.842,552.688 306.899,580.599 254.457,580.599C207.096,580.599 179.605,556.07 165.65,526.469', style: 'fill:rgb(48,9,5);fill-rule:nonzero;'
            end
            _g.s! transform: 'matrix(0.46717,0,0,0.46717,185.613,178.904)' do
              _path d: 'M375,520.13L423.206,492.219C435.896,512.943 452.389,528.166 481.568,528.166C506.099,528.166 521.741,515.901 521.741,498.985C521.741,478.686 505.673,471.496 478.606,459.659L463.809,453.311C421.094,435.13 392.759,412.294 392.759,364.084C392.759,319.68 426.59,285.846 479.454,285.846C517.091,285.846 544.156,298.957 563.608,333.212L517.511,362.814C507.361,344.631 496.369,337.442 479.454,337.442C462.115,337.442 451.119,348.437 451.119,362.814C451.119,380.576 462.115,387.766 487.486,398.762L502.286,405.105C552.611,426.674 580.946,448.662 580.946,498.139C580.946,551.426 539.08,580.604 482.836,580.604C427.86,580.604 392.336,554.386 375,520.13', style: 'fill:rgb(47,9,5);fill-rule:nonzero;'
            end
          end
        end
        _g transform: 'matrix(0.76326,0,0,0.76326,-91.6699,-173.159)' do
          _g.j1! 'serif:id' => 'j', transform: 'matrix(0.46717,0,0,0.46717,186.613,178.904)' do
            _path d: 'M165.65,526.474L213.863,497.296C223.164,513.788 231.625,527.74 251.92,527.74C271.374,527.74 283.639,520.13 283.639,490.53L283.639,289.23L342.842,289.23L342.842,491.368C342.842,552.688 306.899,580.599 254.457,580.599C207.096,580.599 179.605,556.07 165.65,526.469', style: 'fill:rgb(247,223,30);fill-rule:nonzero;'
          end
          _g.s1! 'serif:id' => 's', transform: 'matrix(0.46717,0,0,0.46717,185.613,178.904)' do
            _path d: 'M375,520.13L423.206,492.219C435.896,512.943 452.389,528.166 481.568,528.166C506.099,528.166 521.741,515.901 521.741,498.985C521.741,478.686 505.673,471.496 478.606,459.659L463.809,453.311C421.094,435.13 392.759,412.294 392.759,364.084C392.759,319.68 426.59,285.846 479.454,285.846C517.091,285.846 544.156,298.957 563.608,333.212L517.511,362.814C507.361,344.631 496.369,337.442 479.454,337.442C462.115,337.442 451.119,348.437 451.119,362.814C451.119,380.576 462.115,387.766 487.486,398.762L502.286,405.105C552.611,426.674 580.946,448.662 580.946,498.139C580.946,551.426 539.08,580.604 482.836,580.604C427.86,580.604 392.336,554.386 375,520.13', style: 'fill:rgb(247,223,30);fill-rule:nonzero;'
          end
        end
      end
      _defs do
        _linearGradient id: '_Linear1', x1: '0', y1: '0', x2: '1', y2: '0', gradientUnits: 'userSpaceOnUse', gradientTransform: 'matrix(110.514,-65.1883,65.1883,110.514,284.818,460.929)' do
          _stop offset: '0', style: 'stop-color:rgb(97,18,10);stop-opacity:1'
          _stop offset: '1', style: 'stop-color:rgb(184,34,18);stop-opacity:1'
        end
        _linearGradient id: '_Linear2', x1: '0', y1: '0', x2: '1', y2: '0', gradientUnits: 'userSpaceOnUse', gradientTransform: 'matrix(102.484,-65.5763,65.5763,102.484,288.352,453.55)' do
          _stop offset: '0', style: 'stop-color:rgb(97,18,10);stop-opacity:1'
          _stop offset: '1', style: 'stop-color:rgb(184,34,18);stop-opacity:1'
        end
      end
    end
  end

  # html fetch support
  _json do
    options = parse_request(env).first
    raise ArgumentError.new($load_error) if $load_error

    converted = Ruby2JS.convert(@ruby, options)

    _js converted.to_s

    if @ast
      parsed = Ruby2JS.parse(@ruby).first
      html = Wunderbar::HtmlMarkup.new(Struct.new(:params, :env).new({}, {}))
      ast = html._pre { html._ {walk(parsed)} }
      _parsed ast.serialize({indent: '  '}).join()

      if converted.ast != parsed
        ast = html._pre { html._ {walk(converted.ast)} }
        _filtered ast.serialize({indent: '  '}).join()
      end
    end
  end

  unless env['SERVER_SOFTWARE']
    require 'net/http'
    Thread.new do
      port = env['SERVER_PORT'].to_i

      # wait for server to start
      60.times do
        sleep 0.5
        begin
          status = Net::HTTP.get_response('0.0.0.0','/',port).code
          break if %(200 404 500).include? status
        rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT
        end
      end

      link = "http://localhost:#{port}/"
      if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
        system "start #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /darwin/
        system "open #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
        if ENV['WSLENV'] and not `which wslview`.empty?
          system "wslview #{link}"
        else
          system "xdg-open #{link}"
        end
      end
    end
  end
end

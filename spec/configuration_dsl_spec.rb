gem 'minitest'
require 'minitest/autorun'
require 'ruby2js'

describe Ruby2JS::ConfigurationDSL do
  
  def to_js( string)
    _(Ruby2JS.convert(string, config_file: "spec/config/test_ruby2js.rb").to_s)
  end

  # random tests just to santity check…see return_spec.rb for the full suite
  describe "loaded config file" do
    it "should affect the transpilation" do
      to_js( 'class C; def self.f_n(x_y); FooBar.(x_y); end; def inst; self.class.f_n(); end; end' ).
        must_equal '"use strict"; import FooBar from "@org/package/foobar.js"; class C {static fN(xY) {return FooBar(xY)}; get inst() {return this.constructor.fN()}}'
    end
  end
end

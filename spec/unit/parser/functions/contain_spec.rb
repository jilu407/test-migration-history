#! /usr/bin/env ruby
require 'spec_helper'
require 'puppet_spec/compiler'
require 'puppet/parser/functions'
require 'matchers/containment_matchers'
require 'matchers/resource'
require 'matchers/include_in_order'
require 'unit/parser/functions/shared'


describe 'The "contain" function' do
  include PuppetSpec::Compiler
  include ContainmentMatchers
  include Matchers::Resource

  it "includes the class" do
    catalog = compile_to_catalog(<<-MANIFEST)
      class contained {
        notify { "contained": }
      }

      class container {
        contain contained
      }

      include container
    MANIFEST

    expect(catalog.classes).to include("contained")
  end

  it "includes the class when using a fully qualified anchored name" do
    catalog = compile_to_catalog(<<-MANIFEST)
      class contained {
        notify { "contained": }
      }

      class container {
        contain ::contained
      }

      include container
    MANIFEST

    expect(catalog.classes).to include("contained")
  end

  it "ensures that the edge is with the correct class" do
    catalog = compile_to_catalog(<<-MANIFEST)
      class outer {
        class named { }
        contain named
      }

      class named { }

      include named
      include outer
    MANIFEST

    expect(catalog).to have_resource("Class[Named]")
    expect(catalog).to have_resource("Class[Outer]")
    expect(catalog).to have_resource("Class[Outer::Named]")
    expect(catalog).to contain_class("outer::named").in("outer")
  end

  it "makes the class contained in the current class" do
    catalog = compile_to_catalog(<<-MANIFEST)
      class contained {
        notify { "contained": }
      }

      class container {
        contain contained
      }

      include container
    MANIFEST

    expect(catalog).to contain_class("contained").in("container")
  end

  it "can contain multiple classes" do
    catalog = compile_to_catalog(<<-MANIFEST)
      class a {
        notify { "a": }
      }

      class b {
        notify { "b": }
      }

      class container {
        contain a, b
      }

      include container
    MANIFEST

    expect(catalog).to contain_class("a").in("container")
    expect(catalog).to contain_class("b").in("container")
  end

  context "when containing a class in multiple classes" do
    it "creates a catalog with all containment edges" do
      catalog = compile_to_catalog(<<-MANIFEST)
        class contained {
          notify { "contained": }
        }

        class container {
          contain contained
        }

        class another {
          contain contained
        }

        include container
        include another
      MANIFEST

      expect(catalog).to contain_class("contained").in("container")
      expect(catalog).to contain_class("contained").in("another")
    end

    it "and there are no dependencies applies successfully" do
      manifest = <<-MANIFEST
        class contained {
          notify { "contained": }
        }

        class container {
          contain contained
        }

        class another {
          contain contained
        }

        include container
        include another
      MANIFEST

      expect { apply_compiled_manifest(manifest) }.not_to raise_error
    end

    it "and there are explicit dependencies on the containing class causes a dependency cycle" do
      manifest = <<-MANIFEST
        class contained {
          notify { "contained": }
        }

        class container {
          contain contained
        }

        class another {
          contain contained
        }

        include container
        include another

        Class["container"] -> Class["another"]
      MANIFEST

      expect { apply_compiled_manifest(manifest) }.to raise_error(
        Puppet::Error,
        /Found 1 dependency cycle/
      )
    end
  end

  it "does not create duplicate edges" do
    catalog = compile_to_catalog(<<-MANIFEST)
      class contained {
        notify { "contained": }
      }

      class container {
        contain contained
        contain contained
      }

      include container
    MANIFEST

    contained = catalog.resource("Class", "contained")
    container = catalog.resource("Class", "container")

    expect(catalog.edges_between(container, contained)).to have(1).item
  end

  context "when a containing class has a dependency order" do
    it "the contained class is applied in that order" do
      catalog = compile_to_relationship_graph(<<-MANIFEST)
        class contained {
          notify { "contained": }
        }

        class container {
          contain contained
        }

        class first {
          notify { "first": }
        }

        class last {
          notify { "last": }
        }

        include container, first, last

        Class["first"] -> Class["container"] -> Class["last"]
      MANIFEST

      expect(order_resources_traversed_in(catalog)).to include_in_order(
        "Notify[first]", "Notify[contained]", "Notify[last]"
      )
    end
  end

  describe "When the future parser is in use" do
    require 'puppet/pops'
    before(:each) do
      Puppet[:parser] = 'future'
      compiler  = Puppet::Parser::Compiler.new(Puppet::Node.new("foo"))
      @scope = Puppet::Parser::Scope.new(compiler)
    end

    it_should_behave_like 'all functions transforming relative to absolute names', :function_contain
  end
end

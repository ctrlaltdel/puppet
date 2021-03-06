# the parent class for all of our syntactical objects

require 'puppet'
require 'puppet/util/autoload'

# The base class for all of the objects that make up the parse trees.
# Handles things like file name, line #, and also does the initialization
# for all of the parameters of all of the child objects.
class Puppet::Parser::AST
    # Do this so I don't have to type the full path in all of the subclasses
    AST = Puppet::Parser::AST

    include Puppet::Util::Errors
    include Puppet::Util::MethodHelper
    attr_accessor :line, :file, :parent, :scope

    # Just used for 'tree', which is only used in debugging.
    @@pink = "[0;31m"
    @@green = "[0;32m"
    @@yellow = "[0;33m"
    @@slate = "[0;34m"
    @@reset = "[0m"

    # Just used for 'tree', which is only used in debugging.
    @@indent = " " * 4
    @@indline = @@pink + ("-" * 4) + @@reset
    @@midline = @@slate + ("-" * 4) + @@reset

    @@settypes = {}

    # Just used for 'tree', which is only used in debugging.
    def AST.indention
        return @@indent * @@indention
    end

    # Just used for 'tree', which is only used in debugging.
    def AST.midline
        return @@midline
    end

    # Does this ast object set something?  If so, it gets evaluated first.
    def self.settor?
        if defined? @settor
            @settor
        else
            false
        end
    end

    # Evaluate the current object.  Basically just iterates across all
    # of the contained children and evaluates them in turn, returning a
    # list of all of the collected values, rejecting nil values
    def evaluate(args)
        #Puppet.debug("Evaluating ast %s" % @name)
        value = self.collect { |obj|
            obj.safeevaluate(args)
        }.reject { |obj|
            obj.nil?
        }
    end

    # Throw a parse error.
    def parsefail(message)
        self.fail(Puppet::ParseError, message)
    end

    # Wrap a statemp in a reusable way so we always throw a parse error.
    def parsewrap
        exceptwrap :type => Puppet::ParseError do
            yield
        end
    end

    # The version of the evaluate method that should be called, because it
    # correctly handles errors.  It is critical to use this method because
    # it can enable you to catch the error where it happens, rather than
    # much higher up the stack.
    def safeevaluate(options)
        # We duplicate code here, rather than using exceptwrap, because this
        # is called so many times during parsing.
        begin
            return self.evaluate(options)
        rescue Puppet::Error => detail
            raise adderrorcontext(detail)
        rescue => detail
            error = Puppet::Error.new(detail.to_s)
            # We can't use self.fail here because it always expects strings,
            # not exceptions.
            raise adderrorcontext(error, detail)
        end
    end

    # Again, just used for printing out the parse tree.
    def typewrap(string)
        #return self.class.to_s.sub(/.+::/,'') +
            #"(" + @@green + string.to_s + @@reset + ")"
        return @@green + string.to_s + @@reset +
            "(" + self.class.to_s.sub(/.+::/,'') + ")"
    end

    # Initialize the object.  Requires a hash as the argument, and
    # takes each of the parameters of the hash and calls the settor
    # method for them.  This is probably pretty inefficient and should
    # likely be changed at some point.
    def initialize(args)
        @file = nil
        @line = nil
        set_options(args)
    end
    #---------------------------------------------------------------
    # Now autoload everything.
    @autoloader = Puppet::Util::Autoload.new(self,
        "puppet/parser/ast"
    )
    @autoloader.loadall
end

require 'puppet/parser/ast/leaf'

# $Id$

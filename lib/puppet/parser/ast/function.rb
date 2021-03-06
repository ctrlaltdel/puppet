require 'puppet/parser/ast/branch'

class Puppet::Parser::AST
    # An AST object to call a function.
    class Function < AST::Branch
        attr_accessor :name, :arguments

        @settor = true

        def evaluate(hash)
            # We don't need to evaluate the name, because it's plaintext

            # Just evaluate the arguments
            scope = hash[:scope]

            args = @arguments.safeevaluate(:scope => scope)

            #exceptwrap :message => "Failed to execute %s" % @name,
            #        :type => Puppet::ParseError do
                return scope.send("function_" + @name, args)
            #end
        end

        def initialize(hash)
            @ftype = hash[:ftype] || :rvalue
            hash.delete(:ftype) if hash.include? :ftype

            super(hash)

            # Make sure it's a defined function
            unless @fname = Puppet::Parser::Functions.function(@name)
                raise Puppet::ParseError, "Unknown function %s" % @name
            end

            # Now check that it's been used correctly
            case @ftype
            when :rvalue:
                unless Puppet::Parser::Functions.rvalue?(@name)
                    raise Puppet::ParseError, "Function '%s' does not return a value" %
                        @name
                end
            when :statement:
                if Puppet::Parser::Functions.rvalue?(@name)
                    raise Puppet::ParseError,
                        "Function '%s' must be the value of a statement" %
                        @name
                end
            else
                raise Puppet::DevError, "Invalid function type %s" % @ftype.inspect
            end

            # Lastly, check the arity
        end
    end
end

# $Id$

# The scope class, which handles storing and retrieving variables and types and
# such.

require 'puppet/parser/parser'
require 'puppet/parser/templatewrapper'
require 'puppet/transportable'
require 'strscan'

class Puppet::Parser::Scope
    require 'puppet/parser/resource'

    AST = Puppet::Parser::AST

    Puppet::Util.logmethods(self)

    include Enumerable
    include Puppet::Util::Errors
    attr_accessor :parent, :level, :interp, :source, :host
    attr_accessor :name, :type, :topscope, :base, :keyword
    attr_accessor :top, :translated, :exported, :virtual

    # Whether we behave declaratively.  Note that it's a class variable,
    # so all scopes behave the same.
    @@declarative = true

    # Retrieve and set the declarative setting.
    def self.declarative
        return @@declarative
    end

    def self.declarative=(val)
        @@declarative = val
    end

    # This handles the shared tables that all scopes have.  They're effectively
    # global tables, except that they're only global for a single scope tree,
    # which is why I can't use class variables for them.
    def self.sharedtable(*names)
        attr_accessor(*names)
        @@sharedtables ||= []
        @@sharedtables += names
    end

    # This is probably not all that good of an idea, but...
    # This way a parent can share its tables with all of its children.
    sharedtable :classtable, :definedtable, :exportable, :overridetable, :collecttable

    # Is the value true?  This allows us to control the definition of truth
    # in one place.
    def self.true?(value)
        if value == false or value == "" or value == :undef
            return false
        else
            return true
        end
    end

    # Add to our list of namespaces.
    def add_namespace(ns)
        return false if @namespaces.include?(ns)
        if @namespaces == [""]
            @namespaces = [ns]
        else
            @namespaces << ns
        end
    end

    # Is the type a builtin type?
    def builtintype?(type)
        if typeklass = Puppet::Type.type(type)
            return typeklass
        else
            return false
        end
    end

    # Create a new child scope.
    def child=(scope)
        @children.push(scope)

        # Copy all of the shared tables over to the child.
        @@sharedtables.each do |name|
            scope.send(name.to_s + "=", self.send(name))
        end
    end

    # Verify that the given object isn't defined elsewhere.
    def chkobjectclosure(obj)
        if exobj = @definedtable[obj.ref]
            typeklass = Puppet::Type.type(obj.type)
            if typeklass and ! typeklass.isomorphic?
                Puppet.info "Allowing duplicate %s" % type
            else
                # Either it's a defined type, which are never
                # isomorphic, or it's a non-isomorphic type.
                msg = "Duplicate definition: %s is already defined" % obj.ref

                if exobj.file and exobj.line
                    msg << " in file %s at line %s" %
                        [exobj.file, exobj.line]
                end

                if obj.line or obj.file
                    msg << "; cannot redefine"
                end

                raise Puppet::ParseError.new(msg)
            end
        end

        return true
    end

    # Return the scope associated with a class.  This is just here so
    # that subclasses can set their parent scopes to be the scope of
    # their parent class.
    def class_scope(klass)
        scope = if klass.respond_to?(:classname)
            @classtable[klass.classname]
        else
            @classtable[klass]
        end

        return nil unless scope

        if scope.nodescope? and ! klass.is_a?(AST::Node)
            raise Puppet::ParseError, "Node %s has already been evaluated; cannot evaluate class with same name" % [klass.classname]
        end

        scope
    end

    # Return the list of collections.
    def collections
        @collecttable
    end

    def declarative=(val)
        self.class.declarative = val
    end

    def declarative
        self.class.declarative
    end

    # Test whether a given scope is declarative.  Even though it's
    # a global value, the calling objects don't need to know that.
    def declarative?
        @@declarative
    end

    # Remove a specific child.
    def delete(child)
        @children.delete(child)
    end

    # Remove a resource from the various tables.  This is only used when
    # a resource maps to a definition and gets evaluated.
    def deleteresource(resource)
        if @definedtable[resource.ref]
            @definedtable.delete(resource.ref)
        end

        if @children.include?(resource)
            @children.delete(resource)
        end
    end

    # Are we the top scope?
    def topscope?
        @level == 1
    end

    # Return a list of all of the defined classes.
    def classlist
        unless defined? @classtable
            raise Puppet::DevError, "Scope did not receive class table"
        end
        return @classtable.keys.reject { |k| k == "" }
    end

    # Yield each child scope in turn
    def each
        @children.each { |child|
            yield child
        }
    end

    # Evaluate a list of classes.
    def evalclasses(*classes)
        retval = []
        classes.each do |klass|
            if obj = findclass(klass)
                obj.safeevaluate :scope => self
                retval << klass
            end
        end
        retval
    end

    def exported?
        self.exported
    end

    def findclass(name)
        @namespaces.each do |namespace|
            if r = interp.findclass(namespace, name)
                return r
            end
        end
        return nil
    end

    def finddefine(name)
        @namespaces.each do |namespace|
            if r = interp.finddefine(namespace, name)
                return r
            end
        end
        return nil
    end

    def findresource(string, name = nil)
        if name
            string = "%s[%s]" % [string.capitalize, name]
        end

        @definedtable[string]
    end

    # Recursively complete the whole tree, in preparation for
    # translation or storage.
    def finish
        self.each do |obj|
            obj.finish
        end
    end

    # Initialize our new scope.  Defaults to having no parent and to
    # being declarative.
    def initialize(hash = {})
        @parent = nil
        @type = nil
        @name = nil
        @finished = false
        if hash.include?(:namespace)
            if n = hash[:namespace]
                @namespaces = [n]
            end
            hash.delete(:namespace)
        else
            @namespaces = [""]
        end
        hash.each { |name, val|
            method = name.to_s + "="
            if self.respond_to? method
                self.send(method, val)
            else
                raise Puppet::DevError, "Invalid scope argument %s" % name
            end
        }

        @tags = []

        if @parent.nil?
            unless hash.include?(:declarative)
                hash[:declarative] = true
            end
            self.istop(hash[:declarative])
            @inside = nil
        else
            # This is here, rather than in newchild(), so that all
            # of the later variable initialization works.
            @parent.child = self

            @level = @parent.level + 1
            @interp = @parent.interp
            @source = hash[:source] || @parent.source
            @topscope = @parent.topscope
            #@inside = @parent.inside # Used for definition inheritance
            @host = @parent.host
            @type ||= @parent.type
        end

        # Our child scopes and objects
        @children = []

        # The symbol table for this scope.  This is where we store variables.
        @symtable = {}

        # All of the defaults set for types.  It's a hash of hashes,
        # with the first key being the type, then the second key being
        # the parameter.
        @defaultstable = Hash.new { |dhash,type|
            dhash[type] = {}
        }

        unless @interp
            raise Puppet::DevError, "Scopes require an interpreter"
        end
    end

    # Associate the object directly with the scope, so that contained objects
    # can look up what container they're running within.
    def inside(arg = nil)
        return @inside unless arg

        old = @inside
        @inside = arg
        yield
    ensure
        #Puppet.warning "exiting %s" % @inside.name
        @inside = old
    end

    # Mark that we're the top scope, and set some hard-coded info.
    def istop(declarative = true)
        # the level is mostly used for debugging
        @level = 1

        # The table for storing class singletons.  This will only actually
        # be used by top scopes and node scopes.
        @classtable = {}

        self.class.declarative = declarative

        # The table for all defined objects.
        @definedtable = {}

        # The list of objects that will available for export.
        @exportable = {}

        # The list of overrides.  This is used to cache overrides on objects
        # that don't exist yet.  We store an array of each override.
        @overridetable = Hash.new do |overs, ref|
            overs[ref] = []
        end

        # Eventually, if we support sites, this will allow definitions
        # of nodes with the same name in different sites.  For now
        # the top-level scope is always the only site scope.
        @sitescope = true

        @namespaces = [""]

        # The list of collections that have been created.  This is a global list,
        # but they each refer back to the scope that created them.
        @collecttable = []

        @topscope = self
        @type = "puppet"
        @name = "top"
    end

    # Collect all of the defaults set at any higher scopes.
    # This is a different type of lookup because it's additive --
    # it collects all of the defaults, with defaults in closer scopes
    # overriding those in later scopes.
    def lookupdefaults(type)
        values = {}

        # first collect the values from the parents
        unless @parent.nil?
            @parent.lookupdefaults(type).each { |var,value|
                values[var] = value
            }
        end

        # then override them with any current values
        # this should probably be done differently
        if @defaultstable.include?(type)
            @defaultstable[type].each { |var,value|
                values[var] = value
            }
        end

        #Puppet.debug "Got defaults for %s: %s" %
        #    [type,values.inspect]
        return values
    end

    # Look up all of the exported objects of a given type.
    def lookupexported(type)
        @definedtable.find_all do |name, r|
            r.type == type and r.exported?
        end
    end

    def lookupoverrides(obj)
        @overridetable[obj.ref]
    end

    # Look up a defined type.
    def lookuptype(name)
        finddefine(name) || findclass(name)
    end

    def lookup_qualified_var(name, usestring)
        parts = name.split(/::/)
        shortname = parts.pop
        klassname = parts.join("::")
        klass = findclass(klassname)
        unless klass
            raise Puppet::ParseError, "Could not find class %s" % klassname
        end
        unless kscope = class_scope(klass)
            raise Puppet::ParseError, "Class %s has not been evaluated so its variables cannot be referenced" % klass.classname
        end
        return kscope.lookupvar(shortname, usestring)
    end

    private :lookup_qualified_var

    # Look up a variable.  The simplest value search we do.  Default to returning
    # an empty string for missing values, but support returning a constant.
    def lookupvar(name, usestring = true)
        # If the variable is qualified, then find the specified scope and look the variable up there instead.
        if name =~ /::/
            return lookup_qualified_var(name, usestring)
        end
        # We can't use "if @symtable[name]" here because the value might be false
        if @symtable.include?(name)
            if usestring and @symtable[name] == :undef
                return ""
            else
                return @symtable[name]
            end
        elsif self.parent 
            return @parent.lookupvar(name, usestring)
        elsif usestring
            return ""
        else
            return :undefined
        end
    end

    def namespaces
        @namespaces.dup
    end

    # Add a collection to the global list.
    def newcollection(coll)
        @collecttable << coll
    end

    # Create a new scope.
    def newscope(hash = {})
        hash[:parent] = self
        #debug "Creating new scope, level %s" % [self.level + 1]
        return Puppet::Parser::Scope.new(hash)
    end

    # Is this class for a node?  This is used to make sure that
    # nodes and classes with the same name conflict (#620), which
    # is required because of how often the names are used throughout
    # the system, including on the client.
    def nodescope?
        defined?(@nodescope) and @nodescope
    end

    # Return the list of remaining overrides.
    def overrides
        #@overridetable.collect { |name, overs| overs }.flatten
        @overridetable.values.flatten
    end

    def resources
        @definedtable.values
    end

    # Store the fact that we've evaluated a given class.  We use a hash
    # that gets inherited from the top scope down, rather than a global
    # hash.  We store the object ID, not class name, so that we
    # can support multiple unrelated classes with the same name.
    def setclass(obj)
        if obj.is_a?(AST::HostClass)
            unless obj.classname
                raise Puppet::DevError, "Got a %s with no fully qualified name" %
                    obj.class
            end
            @classtable[obj.classname] = self
        else
            raise Puppet::DevError, "Invalid class %s" % obj.inspect
        end
        if obj.is_a?(AST::Node)
            @nodescope = true
        end
        nil
    end

    # Set all of our facts in the top-level scope.
    def setfacts(facts)
        facts.each { |var, value|
            self.setvar(var, value)
        }
    end

    # Add a new object to our object table and the global list, and do any necessary
    # checks.
    def setresource(obj)
        self.chkobjectclosure(obj)

        @children << obj

        # Mark the resource as virtual or exported, as necessary.
        if self.exported?
            obj.exported = true
        elsif self.virtual?
            obj.virtual = true
        end

        # The global table
        @definedtable[obj.ref] = obj

        return obj
    end

    # Override a parameter in an existing object.  If the object does not yet
    # exist, then cache the override in a global table, so it can be flushed
    # at the end.
    def setoverride(resource)
        resource.override = true
        if obj = @definedtable[resource.ref]
            obj.merge(resource)
        else
            @overridetable[resource.ref] << resource
        end
    end

    # Set defaults for a type.  The typename should already be downcased,
    # so that the syntax is isolated.  We don't do any kind of type-checking
    # here; instead we let the resource do it when the defaults are used.
    def setdefaults(type, params)
        table = @defaultstable[type]

        # if we got a single param, it'll be in its own array
        params = [params] unless params.is_a?(Array)

        params.each { |param|
            #Puppet.debug "Default for %s is %s => %s" %
            #    [type,ary[0].inspect,ary[1].inspect]
            if @@declarative
                if table.include?(param.name)
                    self.fail "Default already defined for %s { %s }" %
                            [type,param.name]
                end
            else
                if table.include?(param.name)
                    # we should maybe allow this warning to be turned off...
                    Puppet.warning "Replacing default for %s { %s }" %
                        [type,param.name]
                end
            end
            table[param.name] = param
        }
    end

    # Set a variable in the current scope.  This will override settings
    # in scopes above, but will not allow variables in the current scope
    # to be reassigned if we're declarative (which is the default).
    def setvar(name,value, file = nil, line = nil)
        #Puppet.debug "Setting %s to '%s' at level %s" %
        #    [name.inspect,value,self.level]
        if @symtable.include?(name)
            if @@declarative
                error = Puppet::ParseError.new("Cannot reassign variable %s" % name)
                if file
                    error.file = file
                end
                if line
                    error.line = line
                end
                raise error
            else
                Puppet.warning "Reassigning %s to %s" % [name,value]
            end
        end
        @symtable[name] = value
    end

    # Return an interpolated string.
    def strinterp(string, file = nil, line = nil)
        # Most strings won't have variables in them.
        ss = StringScanner.new(string)
        out = ""
        while not ss.eos?
            if ss.scan(/^\$\{((\w*::)*\w+)\}|^\$((\w*::)*\w+)/) 
                # If it matches the backslash, then just retun the dollar sign.
                if ss.matched == '\\$'
                    out << '$'
                else # look the variable up
                    out << lookupvar(ss[1] || ss[3]).to_s || ""
                end
            elsif ss.scan(/^\\(.)/)
                # Puppet.debug("Got escape: pos:%d; m:%s" % [ss.pos, ss.matched])
                case ss[1]
                when 'n'
                    out << "\n"
                when 't'
                    out << "\t"
                when 's'
                    out << " "
                when '\\'
                    out << '\\'
                when '$'
                    out << '$'
                else
                    str = "Unrecognised escape sequence '#{ss.matched}'"
                    if file
                        str += " in file %s" % file
                    end
                    if line
                        str += " at line %s" % line
                    end
                    Puppet.warning str
                    out << ss.matched
                end
            elsif ss.scan(/^\$/)
                out << '$'
            elsif ss.scan(/^\\\n/) # an escaped carriage return
                next
            else 
                tmp = ss.scan(/[^\\$]+/)
                # Puppet.debug("Got other: pos:%d; m:%s" % [ss.pos, tmp])
                unless tmp
                    error = Puppet::ParseError.new("Could not parse string %s" %
                        string.inspect)
                    {:file= => file, :line= => line}.each do |m,v|
                        error.send(m, v) if v
                    end
                    raise error
                end
                out << tmp
            end
        end

        return out
    end

    # Add a tag to our current list.  These tags will be added to all
    # of the objects contained in this scope.
    def tag(*ary)
        ary.each { |tag|
            if tag.nil? or tag == ""
                puts caller
                Puppet.debug "got told to tag with %s" % tag.inspect
                next
            end
            unless tag =~ /^\w[-\w]*$/
                fail Puppet::ParseError, "Invalid tag %s" % tag.inspect
            end
            tag = tag.to_s
            unless @tags.include?(tag)
                #Puppet.info "Tagging scope %s with %s" % [self.object_id, tag]
                @tags << tag
            end
        }
    end

    # Return the tags associated with this scope.  It's basically
    # just our parents' tags, plus our type.  We don't cache this value
    # because our parent tags might change between calls.
    def tags
        tmp = [] + @tags
        unless ! defined? @type or @type.nil? or @type == ""
            tmp << @type.to_s
        end
        if @parent
            #info "Looking for tags in %s" % @parent.type
            @parent.tags.each { |tag|
                if tag.nil? or tag == ""
                    Puppet.debug "parent returned tag %s" % tag.inspect
                    next
                end
                unless tmp.include?(tag)
                    tmp << tag
                end
            }
        end
        return tmp.sort.uniq
    end

    # Used mainly for logging
    def to_s
        if self.name
            return "%s[%s]" % [@type, @name]
        else
            return self.type.to_s
        end
    end

    # Convert all of our objects as necessary.
    def translate
        ret = @children.collect do |child|
            case child
            when Puppet::Parser::Resource
                child.to_trans
            when self.class
                child.translate
            else
                devfail "Got %s for translation" % child.class
            end
        end.reject { |o| o.nil? }
        bucket = Puppet::TransBucket.new ret

        case self.type
        when "": bucket.type = "main"
        when nil: devfail "A Scope with no type"
        else
            bucket.type = @type
        end
        if self.name
            bucket.name = self.name
        end
        return bucket
    end

    # Undefine a variable; only used for testing.
    def unsetvar(var)
        if @symtable.include?(var)
            @symtable.delete(var)
        end
    end

    # Return an array of all of the unevaluated objects
    def unevaluated
        ary = @definedtable.find_all do |name, object|
            ! object.builtin? and ! object.evaluated?
        end.collect { |name, object| object }

        if ary.empty?
            return nil
        else
            return ary
        end
    end

    def virtual?
        self.virtual || self.exported?
    end
end

# $Id$

#!/usr/bin/env ruby
#
#  Created by Luke A. Kanies on 2006-11-24.
#  Copyright (c) 2006. All rights reserved.

require 'puppet/external/gratr'

# subscriptions are permanent associations determining how different
# objects react to an event

class Puppet::Relationship < GRATR::Edge
    # Return the callback
    def callback
        if label
            label[:callback]
        else
            nil
        end
    end
    
    # Return our event.
    def event
        if label
            label[:event]
        else
            nil
        end
    end
    
    def initialize(source, target, label = {})
        if label
            unless label.is_a?(Hash)
                raise Puppet::DevError, "The label must be a hash"
            end
        
            if label[:event] and label[:event] != :NONE and ! label[:callback]
                raise Puppet::DevError, "You must pass a callback for non-NONE events"
            end
        else
            label = {}
        end
        
        super(source, target, label)
    end
    
    # Does the passed event match our event?  This is where the meaning
    # of :NONE comes from. 
    def match?(event)
        if self.event.nil? or event == :NONE or self.event == :NONE
            return false
        elsif self.event == :ALL_EVENTS or event == self.event
            return true
        else
            return false
        end
    end
    
    def ref
        "%s => %s" % [source.ref, target.ref]
    end
end

# $Id$

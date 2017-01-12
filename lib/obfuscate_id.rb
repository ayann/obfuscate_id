module ObfuscateId
  def has_obfuscated_id?
    false
  end

  def obfuscate_id(options = {})
    extend ClassMethods
    include InstanceMethods
  end

  def self.hide(str)
    Base64.encode64(str.to_s).gsub(/[\s=]+/, "").tr('+/','-_')
  end

  def self.show(str)
    Base64.decode64(
      "#{str}#{('=' * (4 - str.to_s.length.modulo(4)))}".tr('-_','+/')
    )
  end

  module ClassMethods
    def has_obfuscated_id?
      true
    end

    def deobfuscate_id(obfuscated_id)
      return obfuscated_id unless obfuscated_id.is_a? String
      ObfuscateId.show obfuscated_id
    end
  end

  module InstanceMethods
    def to_param
      ObfuscateId.hide self.id
    end

    # Override ActiveRecord::Persistence#reload
    # passing in an options flag with { no_obfuscated_id: true }
    def reload(options = nil)
      options = (options || {}).merge(no_obfuscated_id: true)

      clear_aggregation_cache
      clear_association_cache

      fresh_object =
        if options && options[:lock]
          self.class.unscoped { self.class.lock(options[:lock]).find(id, options) }
        else
          self.class.unscoped { self.class.find(id, options) }
        end

      @attributes = fresh_object.instance_variable_get('@attributes')
      @new_record = false
      self
    end

    def deobfuscate_id(obfuscated_id)
      self.class.deobfuscate_id(obfuscated_id)
    end
  end
end

ActiveRecord::Base.extend ObfuscateId


module ActiveRecord
  module FinderMethods
    
    old_find = instance_method(:find)

    define_method :find do |*args|
      scope = args.slice!(0)
      options = args.slice!(0) || {}
      if has_obfuscated_id? && !options[:no_obfuscated_id]
        if scope.is_a?(Array)
          scope.map! {|a| deobfuscate_id(a).to_i}
        else
          scope = deobfuscate_id(scope)
        end
      end
      old_find.bind(self).(scope)
    end
  end
end

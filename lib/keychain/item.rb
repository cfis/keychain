
module Sec
  attach_function 'SecKeychainItemDelete', [:pointer], :osstatus
  attach_function 'SecItemAdd', [:pointer, :pointer], :osstatus
  attach_function 'SecItemUpdate', [:pointer, :pointer], :osstatus
  attach_function 'SecKeychainItemCopyKeychain', [:pointer, :pointer], :osstatus

end

class Keychain::Item < Sec::Base
  attr_accessor :attributes
  register_type 'SecKeychainItem'

  def inspect
    "<SecKeychainItem 0x#{@ptr.address.to_s(16)} #{service ? "service: #{service}" : "server: #{server}"} account: #{account}>"
  end

  Sec::ATTR_MAP.values.each do |ruby_name|
    unless method_defined?(ruby_name)
      define_method ruby_name do
        @attributes[ruby_name]
      end
      define_method ruby_name.to_s+'=' do |value|
        @attributes[ruby_name] = value
      end
    end
  end

  # Creates a new keychain item either from an FFI::Pointer or a hash of attributes
  #

  def self.new(attrs_or_pointer)
    if attrs_or_pointer.is_a? Hash
      super(0).tap do |result|
        attrs_or_pointer.each {|k,v| result.send("#{k}=", v)}
      end
    else
      super
    end
  end

  def initialize(*args)
    super
    @attributes = {}
  end

  # Removes the item from the associated keychain
  #
  def delete
    status = Sec.SecKeychainItemDelete(self)
    Sec.check_osstatus(status)
    self
  end

  def password=(value)
    @unsaved_password = value
  end

  def keychain
    out = FFI::MemoryPointer.new :pointer
    status = Sec.SecKeychainItemCopyKeychain(self,out)
    Sec.check_osstatus(status)
    CF::Base.new(out.read_pointer).release_on_gc
  end

  # Fetches the password data associated with the item. This may cause the user to be asked for access
  # @return [String] The password data, an ASCII_8BIT encoded string
  def password
    return @unsaved_password if @unsaved_password
    out_buffer = FFI::MemoryPointer.new(:pointer)
    status = Sec.SecItemCopyMatching({Sec::Query::ITEM_LIST => CF::Array.immutable([self]),
                             Sec::Query::CLASS => klass, 
                             Sec::Query::RETURN_DATA => true}.to_cf, out_buffer)
    Sec.check_osstatus(status)
    CF::Base.typecast(out_buffer.read_pointer).to_s
  end

  def save!(options={})
    if persisted?
      cf_dict = update
    else
      cf_dict = create(options)
    end    
    @unsaved_password = nil
    update_self_from_dictionary(cf_dict)
    cf_dict.release
    self
  end

  def self.from_dictionary_of_attributes(cf_dict)
    new(0).tap {|item| item.send :update_self_from_dictionary, cf_dict}
  end

  def persisted?
    !@ptr.null?
  end

  private

  def create(options)
    result = FFI::MemoryPointer.new :pointer
    query = build_create_query(options)
    query.merge!(build_new_attributes)
    status = Sec.SecItemAdd(query, result);
    Sec.check_osstatus(status)
    cf_dict = CF::Base.typecast(result.read_pointer)
  end

  def update
    status = Sec.SecItemUpdate({Sec::Query::ITEM_LIST => [self], Sec::INVERSE_ATTR_MAP[:klass] => klass}.to_cf, build_new_attributes);
    Sec.check_osstatus(status)

    result = FFI::MemoryPointer.new :pointer
    query = build_refresh_query
    status = Sec.SecItemCopyMatching(query, result);
    Sec.check_osstatus(status)
    cf_dict = CF::Base.typecast(result.read_pointer)
  end
    


  def update_self_from_dictionary(cf_dict)
    if !persisted?
      self.ptr = cf_dict[Sec::Value::REF].to_ptr
      self.retain.release_on_gc
    end
    @attributes = cf_dict.inject({}) do |memo, (k,v)|
      if ruby_name = Sec::ATTR_MAP[k]
        memo[ruby_name] = v.to_ruby
      end
      memo
    end
  end

  def build_create_query options
    query = CF::Dictionary.mutable
    query[Sec::Value::DATA] = CF::Data.from_string(@unsaved_password) if @unsaved_password
    query[Sec::Query::KEYCHAIN] = options[:keychain] if options[:keychain] 
    query[Sec::Query::RETURN_ATTRIBUTES] = CF::Boolean::TRUE
    query[Sec::Query::RETURN_REF] = CF::Boolean::TRUE
    query
  end

  def build_refresh_query
    query = CF::Dictionary.mutable
    query[Sec::Query::ITEM_LIST] = CF::Array.immutable([self])
    query[Sec::Query::RETURN_ATTRIBUTES] = CF::Boolean::TRUE
    query[Sec::Query::RETURN_REF] = CF::Boolean::TRUE
    query[Sec::INVERSE_ATTR_MAP[:klass]] = klass.to_cf
    query
  end

  def build_new_attributes
    new_attributes = CF::Dictionary.mutable
    @attributes.each do |k,v|
      next if k == :created_at || k == :updated_at
      next if k == :klass && persisted?
      k = Sec::INVERSE_ATTR_MAP[k]
      new_attributes[k] = v.to_cf
    end
    new_attributes[Sec::Value::DATA] = CF::Data.from_string(@unsaved_password) if @unsaved_password
    new_attributes
  end
end
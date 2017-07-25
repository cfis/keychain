module Keychain
  class TrustedApplication < Sec::Base
    register_type 'SecTrustedApplication'

    def self.create_from_path(path)
      trusted_app_buffer = FFI::MemoryPointer.new(:pointer)
      status = Sec.SecTrustedApplicationCreateFromPath(path.encode(Encoding::UTF_8), trusted_app_buffer)
      Sec.check_osstatus(status)
      self.new(trusted_app_buffer.read_pointer).release_on_gc
    end
  end
end
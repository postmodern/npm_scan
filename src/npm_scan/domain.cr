require "dns"

module NPMScan
  struct Domain
    RECORD_TYPES = [DNS::RecordType::A, DNS::RecordType::AAAA, DNS::RecordType::MX]

    getter name : String

    def initialize(@name : String)
    end

    def self.from_email(email : String) : Domain
      Domain.new(email.split('@',2).last)
    end

    def registered?(resolver : DNS::Resolver)
      RECORD_TYPES.any? do |record_type|
        response = resolver.query(@name,record_type)
        !response.answers.empty?
      end
    end

    def ==(other : Domain) : Bool
      @name == other.name
    end

    def to_s : String
      @name
    end

    def to_s(io : IO)
      @name.to_s(io)
    end

  end
end

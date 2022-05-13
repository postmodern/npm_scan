module NPMScan
  class DNSCache

    @resolved_domains : Set(String)
    @unresolved_domains : Set(String)

    def initialize
      @resolved_domains   = Set(String).new
      @unresolved_domains = Set(String).new
    end

    def is_resolvable?(domain : String) : Bool
      @resolved_domains.includes?(domain)
    end

    def resolvable!(domain : String)
      @resolved_domains << domain
    end

    def is_unresolvable?(domain : String)
      @unresolved_domains.includes?(domain)
    end

    def unresolvable!(domain : String)
      @unresolved_domains << domain
    end

  end
end

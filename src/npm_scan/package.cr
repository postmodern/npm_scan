module NPMScan
  struct Package

    getter name : String

    getter emails : Array(String)

    getter domains : Array(String)

    def initialize(@name : String, @emails : Array(String))
      @domains = @emails.map { |email|
        EmailAddress.domain_for(email)
      }.uniq
    end

    def is_orphaned? : Bool
      @emails.empty?
    end

    def is_lonely? : Bool
      @domains.size == 1
    end

  end
end

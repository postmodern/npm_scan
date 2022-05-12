module NPMScan
  class OutputFile

    getter path : String

    getter? resume

    def initialize(@path : String, @resume : Bool = false)
      mode = if @resume; "a"
             else        "w"
             end

      @file = File.open(path,mode)
    end

    def <<(line : String)
      @file.puts(line)
      @file.flush
    end

  end
end

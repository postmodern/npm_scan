module NPMScan
  class OutputFile

    getter path : String

    def initialize(@path : String)
      @file = File.open(path,"w")
    end

    def <<(line : String)
      @file.puts(line)
      @file.flush
    end

  end
end

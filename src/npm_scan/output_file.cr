module NPMScan
  class OutputFile < File

    getter path : String

    def self.open(path : String, resume : Bool = false) : OutputFile
      mode = if resume; "a"
             else       "w"
             end

      file = new(path,mode)
      file.flush_on_newline = true
      return file
    end

  end
end

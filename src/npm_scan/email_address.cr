struct EmailAddress

  getter user : String

  getter domain : String

  def self.parse(string : String) : EmailAddress
    user, domain = string.split('@',2)

    return new(user,domain)
  end

end

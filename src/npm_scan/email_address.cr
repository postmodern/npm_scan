module EmailAddress

  def self.domain_for(string : String) : String
    user, domain = string.split('@',2)

    return domain
  end

end

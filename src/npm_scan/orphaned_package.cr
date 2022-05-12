require "./package"
require "./domain"

module NPMScan
  record OrphanedPackage, package : Package, domain : Domain
end

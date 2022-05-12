require "./package"
require "./domain"

module NPMScan
  record Orphaned, package : Package, domain : Domain
end

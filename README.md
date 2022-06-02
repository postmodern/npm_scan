# npm_scan

Scans npmjs.org for NPM packages that can be taken over.

## Build

1. [Install Crystal](https://crystal-lang.org/install/)
2. `shards install`
3. `make`

## Usage

```
$ ./npm_scan --help
usage: npm_scan [options]
usage: npm_scan [options]
    -o, --output FILE                Writes output to file
    -c, --cache FILE                 Write package names to the cache file
    -R, --resume                     Skips package already in the --cache file
    -W, --wordlist-path FILE         Checks the npm packages in the given wordlist_path
    -A, --api-workers NUM            Number of API request workers (Default: 30)
    -D, --dns-workers NUM            Number of DNS request workers (Default: 100)
    -h, --help                       Prints this cruft
```

## Examples

Scan for all packages, log output, and allow resuming after `Ctrl^C`:

```
$ ./npm_scan -c packages.txt -o vuln_packages.txt --resume
```

## Copyright

npm_scan - Scans npmjs.org for NPM packages that can be taken over.

Copyright (C) 2022 Hal Brodigan

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

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
    -o, --output FILE                Writes output to file
    -c, --cache FILE                 Write package names to the cache file
    -R, --resume                     Skips package already in the --cache file
    -W, --wordlist_path FILE         Checks the npm packages in the given wordlist_path
    -h, --help                       Prints this cruft
```

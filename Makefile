all: lib npm_scan npm_downloads

lib:
	shards install

npm_scan: src/npm_scan.cr src/npm_scan/*.cr
	crystal build src/npm_scan.cr

npm_downloads: src/npm_downloads.cr src/npm_scan/*.cr
	crystal build src/npm_downloads.cr

clean:
	rm -f rpm_scan npm_downloads

.PHONY: clean all

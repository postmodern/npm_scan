all: lib npm_scan npm_downloads npm_scrape

lib:
	shards install

npm_scan: src/npm_scan.cr src/npm_scan/*.cr
	crystal build --release src/npm_scan.cr

npm_downloads: src/npm_downloads.cr src/npm_scan/api.cr
	crystal build --release src/npm_downloads.cr

npm_scrape: src/npm_scrape.cr src/npm_scan/api.cr
	crystal build --release src/npm_scrape.cr

clean:
	rm -f rpm_scan npm_downloads npm_scrape

.PHONY: clean all

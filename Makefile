all: npm_scan

npm_scan: src/npm_scan.cr src/npm_scan/*.cr
	crystal build src/npm_scan.cr

clean:
	rm -f rpm_scan

.PHONY: clean all

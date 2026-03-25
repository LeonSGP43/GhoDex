init:
	@echo You probably want to run "zig build" instead.
.PHONY: init

# glad updates the GLAD loader. To use this, place the generated glad.zip
# in this directory next to the Makefile, remove vendor/glad and run this target.
#
# Generator: https://gen.glad.sh/
glad: vendor/glad
.PHONY: glad

vendor/glad: vendor/glad/include/glad/gl.h vendor/glad/include/glad/glad.h

vendor/glad/include/glad/gl.h: glad.zip
	rm -rf vendor/glad
	mkdir -p vendor/glad
	unzip glad.zip -dvendor/glad
	find vendor/glad -type f -exec touch '{}' +

vendor/glad/include/glad/glad.h: vendor/glad/include/glad/gl.h
	@echo "#include <glad/gl.h>" > $@

clean:
	rm -rf \
		zig-out .zig-cache \
		macos/.zig-cache \
		macos/build \
		macos/macos/build \
		macos/GhoDexKit.xcframework \
		macos/GhosttyKit.xcframework
.PHONY: clean

prune-build-artifacts-dry-run:
	bash ./scripts/prune-build-artifacts.sh
.PHONY: prune-build-artifacts-dry-run

prune-build-artifacts:
	bash ./scripts/prune-build-artifacts.sh --apply
.PHONY: prune-build-artifacts
